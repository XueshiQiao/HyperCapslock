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
        // drifts from the dynamic `Calendar.current` window / query-side formatter
        // if the timezone changes while the app runs.
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    private struct StatsDoc: Codable {
        var version: Int
        var days: [String: [String: Int]]
    }

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir: URL
        if AppEnvironment.isUITest {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hypercapslock-uitest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? "me.xueshi.hypercapslock"
            dir = base.appendingPathComponent(bundleID, isDirectory: true)
        }
        return dir.appendingPathComponent("usage_stats.json")
    }()

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
            // Leave the file intact; just start empty in memory (never clobber).
            FileLog.shared.warn("usage_stats.json unreadable — starting empty, file left untouched.")
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
        let cal = Calendar.current
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
        let included: (String) -> Bool
        switch range {
        case .all:
            included = { _ in true }
        case .today, .last7, .last30:
            let cal = Calendar.current
            let today = cal.startOfDay(for: now)
            let back = range == .today ? 0 : (range == .last7 ? 6 : 29)
            let cutoff = cal.date(byAdding: .day, value: -back, to: today) ?? today
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .autoupdatingCurrent
            let cutoffKey = f.string(from: cutoff)
            included = { $0 >= cutoffKey }
        }

        lock.lock(); defer { lock.unlock() }
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
