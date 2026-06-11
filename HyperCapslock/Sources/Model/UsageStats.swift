import Foundation

/// Time window for a statistics query. Day buckets are local-calendar days, so
/// `.today` / `.last7` / `.last30` line up with the user's wall clock.
enum StatsRange: String, CaseIterable, Equatable {
    case today, last7, last30, all
}

/// Thread-safe per-mapping usage counter.
///
/// The CGEventTap callback records a press from its own thread via `record`; the
/// UI reads `snapshot()` / `totals(in:)` on the main thread. Both go through one
/// `NSLock`, mirroring the engine's other shared-state holders
/// (`EngineState`, `MappingsRegistry`). Counts are bucketed per local day so the
/// Statistics page can sum any range; persisted as JSON in the app-support dir,
/// flushed off the hot path on a short debounce (and synchronously at quit).
///
/// Counting policy (intentional): one press == one physical key-down of a
/// configured trigger. OS auto-repeat does NOT increment (the chord re-fire path
/// never reaches `record`); the bare CapsLock toggle when no single-tap mapping
/// exists is not a mapping and is not counted. Counters are keyed by the
/// trigger's stable `triggerUniqueID`, so rebinding a key keeps its history.
final class UsageStats {
    static let shared = UsageStats()

    private let lock = NSLock()
    /// triggerID → ("yyyy-MM-dd" local day → count).
    private var counts: [String: [String: Int]] = [:]
    private var dirty = false
    private var loaded = false

    /// Cached "today" key + its `[start, end)` wall-clock window so the hot path
    /// resolves the calendar day at most once per day, not once per keystroke.
    private var cachedDayKey = ""
    private var cachedDayStart = Date.distantPast
    private var cachedDayEnd = Date.distantPast

    /// Serial queue for all disk IO — keeps writes off the tap thread and
    /// serialized with each other (no concurrent writers).
    private let io = DispatchQueue(label: "me.xueshi.hypercapslock.usagestats.io", qos: .utility)
    private let flushDelaySeconds: TimeInterval = 10

    /// POSIX day formatter, used only under `lock` (record + load), so its
    /// non-reentrant `string(from:)` is never called concurrently.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        // Track system timezone dynamically so the record-side day key never
        // drifts from the day-boundary window / query-side cutoff if the timezone
        // changes while the app runs.
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// A Gregorian calendar in the current timezone, used for ALL day-boundary
    /// math (startOfDay, ±days). The day keys are formatted with the Gregorian
    /// `dayFormatter`, so the boundaries must be Gregorian too — otherwise a user
    /// whose *system* calendar is non-Gregorian (Buddhist / Japanese / Hebrew…)
    /// would get boundaries that disagree with the "yyyy-MM-dd" labels.
    private static func localCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .autoupdatingCurrent
        return cal
    }

    private struct StatsDoc: Codable {
        var version: Int
        var days: [String: [String: Int]]
    }

    // Path resolution (uitest temp-dir isolation + bundle-id dir) is the single
    // source of truth in `AppEnvironment.appSupportDirectory`, shared with ConfigStore.
    private let fileURL = AppEnvironment.appSupportDirectory.appendingPathComponent("usage_stats.json")

    private init() {}

    // MARK: - Load (call once at launch, before the tap can record)

    func load() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let doc = try? JSONDecoder().decode(StatsDoc.self, from: data) {
            counts = doc.days
            FileLog.shared.info("UsageStats loaded: \(counts.count) tracked trigger(s).")
        } else {
            // We start empty, and the first recorded press will overwrite this
            // file — so move the unreadable original aside first (mirrors
            // ConfigStore's parse-failure backup). Never silently destroy a user's
            // accumulated history.
            let corruptURL = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: corruptURL)
            do {
                try FileManager.default.moveItem(at: fileURL, to: corruptURL)
                FileLog.shared.warn("usage_stats.json unreadable — preserved as \(corruptURL.lastPathComponent), starting empty.")
            } catch {
                FileLog.shared.error("usage_stats.json unreadable and backup failed (\(error.localizedDescription)); starting empty.")
            }
        }
    }

    // MARK: - Record (hot path, any thread)

    /// Count one physical press of the trigger identified by `triggerID`
    /// (a `triggerUniqueID(...)` value). Cheap: a dict bump under the lock plus a
    /// debounced background flush.
    func record(_ triggerID: String) {
        let now = Date()
        lock.lock()
        let day = dayKeyLocked(now)
        counts[triggerID, default: [:]][day, default: 0] += 1
        let wasDirty = dirty
        dirty = true
        lock.unlock()
        if !wasDirty { io.asyncAfter(deadline: .now() + flushDelaySeconds) { [weak self] in self?.writeIfDirty() } }
    }

    /// Resolve `now`'s local day key, recomputing the cached day window only when
    /// `now` has crossed midnight. MUST be called with `lock` held.
    private func dayKeyLocked(_ now: Date) -> String {
        if now >= cachedDayStart && now < cachedDayEnd { return cachedDayKey }
        let cal = Self.localCalendar()
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        cachedDayStart = start
        cachedDayEnd = end
        cachedDayKey = Self.dayFormatter.string(from: start)
        return cachedDayKey
    }

    // MARK: - Queries (main thread)

    /// Per-trigger totals over `range` (only triggers with a non-zero count).
    /// Day keys are zero-padded ISO dates, so a lexicographic `>=` against the
    /// cutoff key correctly selects the in-range days.
    func totals(in range: StatsRange, asOf now: Date = Date()) -> [String: Int] {
        // Hold the lock across the whole query so the cutoff can reuse the static
        // `dayFormatter` (only ever touched under `lock`) — no per-call DateFormatter
        // allocation on the page's 1.5s refresh tick.
        lock.lock(); defer { lock.unlock() }
        let included: (String) -> Bool
        switch range {
        case .all:
            included = { _ in true }
        case .today, .last7, .last30:
            let cal = Self.localCalendar()
            let today = cal.startOfDay(for: now)
            let back = range == .today ? 0 : (range == .last7 ? 6 : 29)
            let cutoff = cal.date(byAdding: .day, value: -back, to: today) ?? today
            let cutoffKey = Self.dayFormatter.string(from: cutoff)
            included = { $0 >= cutoffKey }
        }
        var out: [String: Int] = [:]
        for (trigger, days) in counts {
            var sum = 0
            for (day, c) in days where included(day) { sum += c }
            if sum > 0 { out[trigger] = sum }
        }
        return out
    }

    /// Whether any press has ever been recorded (drives the "nothing yet" empty
    /// state vs. the "nothing in this range" empty state).
    func hasAnyData() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return counts.contains { !$0.value.isEmpty }
    }

    // MARK: - Reset

    func reset() {
        lock.lock()
        counts = [:]
        dirty = false
        lock.unlock()
        // A destructive, data-clearing op — record it.
        FileLog.shared.info("UsageStats reset — all recorded press counts cleared.")
        io.async { [weak self] in self?.persist([:]) }
    }

    // MARK: - Persistence

    /// Force a synchronous flush. Called at app termination, where a queued
    /// async flush might not run before the process exits.
    func flushNow() {
        io.sync { self.writeIfDirty() }
    }

    private func writeIfDirty() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        dirty = false
        let snapshot = counts
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ snapshot: [String: [String: Int]]) {
        let doc = StatsDoc(version: 1, days: snapshot)
        do {
            let data = try JSONEncoder().encode(doc)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            FileLog.shared.error("Failed to write usage_stats.json: \(error)")
        }
    }
}
