import Foundation

/// The runtime environment a binding's conditions are evaluated against.
/// Built once per key event from cached state; never touches AppKit.
struct RuntimeContext: Equatable {
  var frontmostBundleID: String?
}

/// A single condition, internally tagged by `type`. v1 ships `frontmost_app`.
///
/// An unrecognized type decodes to `.unknown` and is treated as *never*
/// satisfied (fail-closed), so a condition written by a newer build stays
/// dormant on an older build instead of misfiring — and decoding never throws,
/// which would otherwise fail the whole config load.
enum Condition: Equatable {
  /// Matches when the frontmost app is in `include` (allowlist) and not in
  /// `exclude` (denylist). Bundle ids compared case-insensitively.
  case frontmostApp(include: [String], exclude: [String])
  case unknown

  func isSatisfied(_ ctx: RuntimeContext) -> Bool {
    switch self {
    case .frontmostApp(let include, let exclude):
      // A degenerate condition with neither list matches nothing.
      if include.isEmpty && exclude.isEmpty { return false }
      guard let app = ctx.frontmostBundleID?.lowercased() else { return false }
      if !include.isEmpty && !include.contains(where: { $0.lowercased() == app }) { return false }
      if exclude.contains(where: { $0.lowercased() == app }) { return false }
      return true
    case .unknown:
      return false
    }
  }
}

extension Condition: Codable {
  private enum CodingKeys: String, CodingKey { case type, include, exclude }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
    switch type {
    case "frontmost_app":
      self = .frontmostApp(
        include: try c.decodeIfPresent([String].self, forKey: .include) ?? [],
        exclude: try c.decodeIfPresent([String].self, forKey: .exclude) ?? [])
    default:
      self = .unknown
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .frontmostApp(let include, let exclude):
      try c.encode("frontmost_app", forKey: .type)
      if !include.isEmpty { try c.encode(include, forKey: .include) }
      if !exclude.isEmpty { try c.encode(exclude, forKey: .exclude) }
    case .unknown:
      try c.encode("unknown", forKey: .type)
    }
  }
}

/// A conditional override under a trigger. When the trigger fires, bindings are
/// evaluated in declaration order and the first whose conditions all hold wins.
/// References an action the same way a mapping does: `actionId` preferred,
/// inline fallback. A binding must carry a non-empty `when` (validated on save);
/// the default/global action lives in the mapping's `actionId`, never here.
struct MappingBinding: Equatable {
  var when: [Condition]
  var actionId: String?
  var inlineAction: ActionConfig?

  init(when: [Condition] = [], actionId: String? = nil, inlineAction: ActionConfig? = nil) {
    self.when = when
    self.actionId = actionId
    self.inlineAction = inlineAction
  }

  /// All conditions must hold (AND). An empty `when` never matches (defensive —
  /// such a binding is rejected on save).
  func matches(_ ctx: RuntimeContext) -> Bool {
    guard !when.isEmpty else { return false }
    return when.allSatisfy { $0.isSatisfied(ctx) }
  }
}

extension MappingBinding: Codable {
  private enum CodingKeys: String, CodingKey {
    case when
    case actionId = "action_id"
    case action
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.when = try c.decodeIfPresent([Condition].self, forKey: .when) ?? []
    self.actionId = try c.decodeIfPresent(String.self, forKey: .actionId)
    self.inlineAction = try c.decodeIfPresent(ActionConfig.self, forKey: .action)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(when, forKey: .when)
    try c.encodeIfPresent(actionId, forKey: .actionId)
    try c.encodeIfPresent(inlineAction, forKey: .action)
  }
}
