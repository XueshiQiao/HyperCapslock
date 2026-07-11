import Foundation
import Aptabase

/// App-wide wrapper over the Aptabase SDK — the single place that knows the app
/// key and owns the opt-out gate. Callers use `Analytics.shared` and never touch
/// `Aptabase.shared` directly (one source of truth).
///
/// Privacy stance (opt-out, on by default, toggleable in Settings):
///   - Disabled entirely under `-uitest` — CI / UI-test runs never phone home.
///   - When the user has it OFF we never even call `initialize`, so zero network
///     traffic leaves the machine.
///   - We send ONLY anonymous, non-identifying data: event names, an action's
///     *type* enum (`ActionConfig.kindTag`), and stable `builtin.*` ids. We NEVER
///     send keystrokes or user content (shell commands, bundle ids, custom action
///     names, input-source ids). Aptabase itself attaches only coarse context
///     (app version, macOS version, locale, device class) — no PII, no cross-
///     session identifier.
final class Analytics {
  static let shared = Analytics()

  /// US-region Aptabase app key. The `A-US-` prefix routes the SDK to the US
  /// ingest endpoint automatically.
  private static let appKey = "A-US-8795945222"

  private let lock = NSLock()
  private var enabled = false
  private var initialized = false

  private init() {}

  /// Whether analytics is currently active (thread-safe). The roll-up reads this
  /// to decide whether to emit events or just skip-and-advance its watermark,
  /// without touching the main-actor-isolated `AppState`.
  var isEnabled: Bool {
    lock.lock(); defer { lock.unlock() }
    return enabled
  }

  /// Call once at launch with the persisted opt-out preference.
  func configure(enabled: Bool) { setEnabled(enabled) }

  /// Flip the opt-out toggle (launch or runtime). Initializes the SDK lazily the
  /// first time analytics is enabled, so a user who leaves it off never triggers
  /// any Aptabase setup. No-op under `-uitest`.
  func setEnabled(_ on: Bool) {
    guard !AppEnvironment.isUITest else { return }
    lock.lock(); defer { lock.unlock() }
    enabled = on
    if on && !initialized {
      Aptabase.shared.initialize(appKey: Analytics.appKey)
      initialized = true
    }
    FileLog.shared.info("Analytics enabled=\(on) initialized=\(initialized)")
  }

  /// Track a non-identifying event. Silently drops if analytics is disabled or
  /// under `-uitest`. `props` values must be strings/numbers (Aptabase allows
  /// only those) and MUST NOT carry user content — pass only enums / stable ids /
  /// aggregate counts (see the type doc).
  func track(_ event: String, _ props: [String: Any] = [:]) {
    guard !AppEnvironment.isUITest else { return }
    var send = false
    lock.lock(); send = enabled && initialized; lock.unlock()
    guard send else { return }
    if props.isEmpty {
      Aptabase.shared.trackEvent(event)
    } else {
      Aptabase.shared.trackEvent(event, with: props)
    }
    FileLog.shared.info("Analytics event: \(event)\(props.isEmpty ? "" : " \(props)")")
  }

  // MARK: - Mapping events

  /// Build the PII-safe property bag for a mapping add/remove event from the same
  /// `(actionId, inlineAction)` pair that `upsert`/entries carry. Sends the
  /// action's `kindTag` always, plus the `builtin.*` id when (and only when) the
  /// action is a built-in — never a custom action's id or any payload.
  static func mappingProps(actionId: String?, inlineAction: ActionConfig?) -> [String: String] {
    var props: [String: String] = [:]
    if let inline = inlineAction {
      props["action_type"] = inline.kindTag
    } else if let id = actionId {
      props["action_type"] = ActionsRegistry.shared.action(byID: id)?.config.kindTag ?? "unknown"
      if id.hasPrefix("builtin.") { props["builtin_id"] = id }
    } else {
      props["action_type"] = "unknown"
    }
    return props
  }
}
