import Foundation

/// Daily roll-up that turns the LOCAL per-trigger usage counts (`UsageStats`)
/// into anonymous, aggregated `feature_used` analytics — answering "how often is
/// each feature actually used?" across users, so we can see which actions earn
/// their keep and which can be retired.
///
/// Design constraints:
///   - **No firehose**: we NEVER report per-keypress. We aggregate whole days.
///   - **Never touch the sensitive `usage_stats.json` write path**: we only read
///     a snapshot of `UsageStats`; the roll-up watermark lives in its OWN small
///     file (`analytics_report_state.json`), written single-threaded + atomically.
///   - **Idempotent**: a watermark (`reported_through_day`) marks the last
///     completed day already reported, so each day is reported at most once no
///     matter how often the app launches. Only days strictly BEFORE today are
///     reported — today's partial counts wait until the day closes.
///   - **No pre-install backfill**: the first run seeds the watermark at
///     yesterday and reports nothing.
///   - **Privacy**: emits only the same PII-safe fields as mapping events
///     (`action_type` enum + `builtin.*` id) plus the day and an aggregate count —
///     never keystrokes or user content. While analytics is OFF, days are skipped
///     (watermark still advances) so re-enabling never dumps the disabled period.
final class UsageRollup {
  static let shared = UsageRollup()

  private let stateURL = AppEnvironment.appSupportDirectory.appendingPathComponent("analytics_report_state.json")
  private var timer: Timer?

  private struct State: Codable {
    var reportedThroughDay: String
    enum CodingKeys: String, CodingKey { case reportedThroughDay = "reported_through_day" }
  }

  private init() {}

  /// Run once now, then re-check every 6h (covers a machine left on for days so
  /// the day boundary is crossed without needing a relaunch). No-op under -uitest.
  func start() {
    // Idempotent: a second start() must not schedule a second timer.
    guard !AppEnvironment.isUITest, timer == nil else { return }
    run()
    let t = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.run() }
    t.tolerance = 600
    timer = t
  }

  /// Report every completed, not-yet-reported day, then advance the watermark.
  func run() {
    guard !AppEnvironment.isUITest else { return }
    let (today, yesterday) = UsageStats.shared.todayAndYesterdayKeys()

    // First run: establish the watermark at yesterday and report nothing — we
    // don't backfill pre-install history.
    guard let watermark = loadWatermark() else {
      saveWatermark(yesterday)
      FileLog.shared.info("UsageRollup: initialized watermark=\(yesterday) (no backfill).")
      return
    }
    // Day keys are zero-padded ISO, so lexicographic compare == chronological.
    // A clock/timezone move backwards (yesterday <= watermark) reports nothing and
    // doesn't advance — never double-reports.
    guard yesterday > watermark else { return }

    if Analytics.shared.isEnabled {
      emit(reportableAfter: watermark, before: today)
    } else {
      FileLog.shared.info("UsageRollup: analytics off — skipping (\(watermark), \(today)), advancing watermark.")
    }
    saveWatermark(yesterday)
  }

  /// Aggregate the counts of every day in `(watermark, today)` by resolved action
  /// type and emit one `feature_used` event per (day, action_type[, builtin_id]).
  private func emit(reportableAfter watermark: String, before today: String) {
    let all = UsageStats.shared.snapshotAllDays()
    // triggerID -> current action, for resolving each day's counts. Best-effort:
    // a since-deleted / rebound trigger resolves via the CURRENT registry (or
    // "unknown" if the trigger no longer exists).
    var entryByTrigger: [String: ActionMappingEntry] = [:]
    for e in MappingsRegistry.shared.snapshot() { entryByTrigger[triggerUniqueID(e.trigger)] = e }

    // day -> "action_type\u{1F}builtin_id" -> summed count.
    var perDay: [String: [String: Int]] = [:]
    for (trigger, days) in all {
      let props = entryByTrigger[trigger].map {
        Analytics.mappingProps(actionId: $0.actionId, inlineAction: $0.inlineAction)
      } ?? ["action_type": "unknown"]
      let groupKey = (props["action_type"] ?? "unknown") + "\u{1F}" + (props["builtin_id"] ?? "")
      for (day, c) in days where day > watermark && day < today {
        perDay[day, default: [:]][groupKey, default: 0] += c
      }
    }

    var events = 0
    for (day, groups) in perDay {
      for (groupKey, count) in groups {
        let parts = groupKey.components(separatedBy: "\u{1F}")
        var p: [String: Any] = ["day": day, "action_type": parts[0], "count": count]
        if parts.count > 1, !parts[1].isEmpty { p["builtin_id"] = parts[1] }
        Analytics.shared.track("feature_used", p)
        events += 1
      }
    }
    FileLog.shared.info("UsageRollup: reported \(events) feature_used event(s) for days (\(watermark), \(today)).")
  }

  private func loadWatermark() -> String? {
    guard let data = try? Data(contentsOf: stateURL),
          let s = try? JSONDecoder().decode(State.self, from: data) else { return nil }
    return s.reportedThroughDay
  }

  private func saveWatermark(_ day: String) {
    do {
      let data = try JSONEncoder().encode(State(reportedThroughDay: day))
      try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: stateURL, options: .atomic)
    } catch {
      FileLog.shared.error("UsageRollup: failed to persist watermark: \(error)")
    }
  }
}
