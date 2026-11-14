import SwiftUI
import AppKit

// The Mappings page can render in several visual styles (see `MappingsViewStyle`).
// This file holds the per-style sub-views plus the shared row/trigger components
// they reuse, so adding a new style is just: a new enum case + a new sub-view.
// `MappingsPage` (in MappingsCard.swift) owns the toolbar/sheet/state and simply
// dispatches to the style selected in `AppConfig.mappingsViewStyle`.

// MARK: - Keycaps

/// Which keycap look the trigger chips use. `.raised` is the neutral 3D physical
/// keycap (used by the keyboard view); `.glass` is the colorful frosted keycap the
/// grouped list uses.
enum KeycapStyle { case raised, glass }

/// Renders one keycap chip. `modifier` marks the Caps / Shift keycap so it can read
/// as a distinct (cooler) color from the actual key.
@ViewBuilder func keycapView(_ text: String, _ style: KeycapStyle, modifier: Bool = false) -> some View {
    switch style {
    case .raised: Keycap(text)
    case .glass:  GlassCap(text, modifier: modifier)
    }
}

/// Frosted-glass keycap for the grouped list's trigger chips.
///
/// - The *key* gets the colorful blue→violet frosted look (a real
///   `.ultraThinMaterial` blur).
/// - A *modifier* (Caps / Shift) gets a cooler slate tint with NO material — so it
///   reads as a clearly different color AND a row composites at most one backdrop
///   blur instead of two (lighter to draw while scrolling / dragging the window).
///
/// No drop shadow: one chip per key plus a pill per row made the cumulative
/// offscreen shadow passes a measurable cost; the light border carries the edge.
struct GlassCap: View {
    let text: String
    let modifier: Bool
    init(_ text: String, modifier: Bool = false) { self.text = text; self.modifier = modifier }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(textColor(dark))
            .padding(.horizontal, 9).frame(minWidth: 29, minHeight: 27)
            .background(fill(dark))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.4 : 0.85), .white.opacity(0.1)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private func textColor(_ dark: Bool) -> Color {
        if modifier { return dark ? Color(red: 0.90, green: 0.93, blue: 1.0) : Color(red: 0.20, green: 0.30, blue: 0.60) }
        return dark ? Color(red: 0.93, green: 0.95, blue: 1.0) : Color(red: 0.24, green: 0.26, blue: 0.46)
    }

    @ViewBuilder private func fill(_ dark: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if modifier {
            // Bright periwinkle (no backdrop blur) — still distinct from the frosted
            // key, but lively rather than gray.
            shape.fill(LinearGradient(
                colors: dark ? [Color(red: 0.36, green: 0.43, blue: 0.64), Color(red: 0.27, green: 0.33, blue: 0.52)]
                             : [Color(red: 0.82, green: 0.89, blue: 1.0), Color(red: 0.66, green: 0.77, blue: 1.0)],
                startPoint: .top, endPoint: .bottom))
        } else {
            // Colorful frosted glass (the look kept from the chosen style).
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(LinearGradient(
                    colors: [Color(red: 0.42, green: 0.58, blue: 1.0).opacity(dark ? 0.42 : 0.30),
                             Color(red: 0.66, green: 0.46, blue: 1.0).opacity(dark ? 0.32 : 0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }
}

/// A raised, physical-looking keycap — ported from the design mockup
/// (`docs/design/mappings-mockups.html`). Adapts to light/dark so it reads as a
/// real key in either appearance (light-gray cap in light mode, graphite in dark).
struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(dark ? Color(red: 0.89, green: 0.91, blue: 0.95)
                                  : Color(red: 0.13, green: 0.13, blue: 0.15))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 25)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(
                        colors: dark ? [Color(red: 0.20, green: 0.24, blue: 0.30), Color(red: 0.115, green: 0.145, blue: 0.19)]
                                     : [Color.white, Color(red: 0.90, green: 0.91, blue: 0.93)],
                        startPoint: .top, endPoint: .bottom)))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: dark ? [Color.white.opacity(0.16), Color.black.opacity(0.55)]
                                     : [Color.white, Color.black.opacity(0.20)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.35 : 0.16), radius: 1.2, y: 1)
    }
}

// MARK: - Shared trigger chips

/// The trigger rendered as keycap chips (`Caps + H`, `Caps ×2`, `⌘ ×2`, …).
/// Shared by every style so a trigger reads the same everywhere.
struct TriggerChips: View {
    let trigger: Trigger
    var style: KeycapStyle = .raised

    var body: some View {
        HStack(spacing: 5) {
            switch trigger {
            case .singleTapHyper:
                cap("Caps", modifier: true); times; cap("1")
            case .doubleTapHyper:
                cap("Caps", modifier: true); times; cap("2")
            case .doubleTapModifier(let m):
                cap(modifierGlyph(m), modifier: true); times; cap("2")
            case .hyperPlusKey(let key, let withShift):
                cap("Caps", modifier: true); plus
                if withShift { cap("Shift", modifier: true); plus }
                cap(keyCodeDisplay(key))
            }
        }
    }

    @ViewBuilder private func cap(_ t: String, modifier: Bool = false) -> some View {
        keycapView(t, style, modifier: modifier)
    }
    private var plus: some View { Text("+").foregroundColor(.secondary).font(.caption) }
    private var times: some View { Text("×").foregroundColor(.secondary).font(.caption) }
}

// MARK: - Trigger categories (for the grouped style)

/// Buckets a trigger into one of the grouped-style sections. Declaration order
/// is section order.
enum TriggerCategory: CaseIterable {
    case capsKey, capsShiftKey, singleTap, doubleTap, doubleTapModifier

    var nameKey: String {
        switch self {
        case .capsKey:           return "mappings.group.caps_key"
        case .capsShiftKey:      return "mappings.group.caps_shift_key"
        case .singleTap:         return "mappings.group.single_tap"
        case .doubleTap:         return "mappings.group.double_tap"
        case .doubleTapModifier: return "mappings.group.double_tap_modifier"
        }
    }
}

func triggerCategory(_ t: Trigger) -> TriggerCategory {
    switch t {
    case .hyperPlusKey(_, let withShift): return withShift ? .capsShiftKey : .capsKey
    case .singleTapHyper:                 return .singleTap
    case .doubleTapHyper:                 return .doubleTap
    case .doubleTapModifier:              return .doubleTapModifier
    }
}

// MARK: - Action pill

/// The action half of a row / tooltip: the action icon in its category color +
/// label, inside a solid category-tinted capsule so it reads as one distinct,
/// high-contrast unit. Shared by the grouped rows, the keyboard's Other Triggers,
/// the per-app rules popover, and the keyboard hover tooltip.
struct ActionPill: View {
    let display: ActionDisplay
    let accent: Color

    var body: some View {
        let tint = display.invalid ? Color.orange : accent
        return HStack(spacing: 6) {
            if let icon = display.icon {
                Image(nsImage: icon).resizable().frame(width: 15, height: 15)
            } else {
                Image(systemName: display.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            Text(display.text).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(
            Capsule().fill(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .help(display.text)
    }
}

/// Category accent color for the action a mapping is *represented* by (see
/// `representativeActionRef` — a noop-default mapping borrows its first real
/// per-app action), so the pill/bar color always matches the shown label; orange
/// when that action is unresolved/invalid.
@MainActor
func actionAccent(_ entry: ActionMappingEntry, invalid: Bool) -> Color {
    if invalid { return .orange }
    let ref = representativeActionRef(entry)
    return ActionsRegistry.shared.resolve(actionId: ref.actionId, inline: ref.inline)
        .map(actionCategoryColor) ?? .secondary
}

// MARK: - Cached app metadata & read-only Per-App rules popover

@MainActor
private enum AppMetadataCache {
    struct Entry { let name: String; let icon: NSImage? }
    private static var cache: [String: Entry] = [:]

    static func lookup(_ bundleID: String) -> Entry {
        let key = bundleID.lowercased()
        if let hit = cache[key] { return hit }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let raw = FileManager.default.displayName(atPath: url.path)
            let name = raw.hasSuffix(".app") ? String(raw.dropLast(4)) : raw
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let entry = Entry(name: name, icon: icon)
            cache[key] = entry
            return entry
        }
        let fallback = Entry(name: bundleID, icon: nil)
        cache[key] = fallback
        return fallback
    }
}

private struct NSViewAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onResolve(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView) }
    }
}

/// Coordinates both click-to-pin and dwell-hover presentation for `PerAppRulesBadge`
/// without flickering when AppKit transfers key-window focus to `NSPopover`.
@MainActor
private final class HoverPopoverCoordinator: ObservableObject {
    @Published var isPresented = false
    weak var badgeNSView: NSView?
    weak var popoverNSView: NSView?
    private var isPinned = false
    private var openTimer: DispatchWorkItem?
    private var eventMonitor: Any?

    func togglePin() {
        openTimer?.cancel()
        openTimer = nil
        if isPresented {
            isPinned = false
            isPresented = false
            stopMonitor()
        } else {
            isPinned = true
            isPresented = true
            stopMonitor()
        }
    }

    func setBadgeHover(_ hovering: Bool) {
        if hovering {
            guard !isPresented else { return }
            openTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isPresented else { return }
                self.isPinned = false
                self.isPresented = true
                self.startMonitor()
            }
            openTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        } else {
            openTimer?.cancel()
            openTimer = nil
        }
    }

    func handlePresentationChanged(_ open: Bool) {
        if !open {
            isPinned = false
            openTimer?.cancel()
            openTimer = nil
            stopMonitor()
        }
    }

    func teardown() {
        openTimer?.cancel()
        openTimer = nil
        stopMonitor()
    }

    private func startMonitor() {
        stopMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleEvent(event)
            }
            return event
        }
    }

    private func stopMonitor() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        guard isPresented, !isPinned else { stopMonitor(); return }
        let loc = NSEvent.mouseLocation
        let inBadge: Bool = {
            guard let v = badgeNSView, let w = v.window else { return false }
            let screenRect = w.convertToScreen(v.convert(v.bounds, to: nil)).insetBy(dx: -12, dy: -12)
            return screenRect.contains(loc)
        }()
        let inPopover: Bool = {
            guard let w = popoverNSView?.window else { return false }
            return w.frame.insetBy(dx: -12, dy: -12).contains(loc)
        }()
        if event.type == .scrollWheel && !inPopover {
            isPresented = false
            stopMonitor()
            return
        }
        if !inBadge && !inPopover {
            isPresented = false
            stopMonitor()
        }
    }

    deinit {
        openTimer?.cancel()
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
        }
    }
}

/// Compact inline indicator for a mapping's per-app rules (Slot ①, placed just
/// left of `ActionPill`). Shows miniature real app icons + rule count (or ⚠️ in
/// orange when a rule action is unresolved) without ever increasing single-line
/// row height. Clicking or hovering opens the read-only `PerAppRulesPopover`.
struct PerAppRulesBadge: View {
    let entry: ActionMappingEntry
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.colorScheme) private var scheme
    @StateObject private var popover = HoverPopoverCoordinator()

    private var bindings: [MappingBinding] { entry.bindings }

    private var distinctAppIcons: [NSImage] {
        var seen = Set<String>()
        var icons: [NSImage] = []
        for binding in bindings {
            for cond in binding.when {
                if case .frontmostApp(let include, let exclude) = cond {
                    for bid in include + exclude where seen.insert(bid.lowercased()).inserted {
                        if let icon = AppMetadataCache.lookup(bid).icon {
                            icons.append(icon)
                            if icons.count >= 3 { return icons }
                        }
                    }
                }
            }
        }
        return icons
    }

    var body: some View {
        let invalid = bindings.contains { ActionsRegistry.shared.resolve($0) == nil }
        let dark = scheme == .dark
        let icons = invalid ? [] : distinctAppIcons
        let triggerID = triggerUniqueID(entry.trigger)

        Button {
            popover.togglePin()
        } label: {
            HStack(spacing: 4) {
                if invalid {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                } else if !icons.isEmpty {
                    HStack(spacing: -3) {
                        ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 14, height: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        }
                    }
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text("\(bindings.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(
                Capsule().fill((invalid ? Color.orange : Color.accentColor).opacity(dark ? 0.18 : 0.12))
            )
            .overlay(
                Capsule().strokeBorder((invalid ? Color.orange : Color.accentColor).opacity(dark ? 0.28 : 0.18), lineWidth: 0.5)
            )
            .foregroundStyle(invalid ? Color.orange : Color.accentColor)
            .background(NSViewAnchor { popover.badgeNSView = $0 })
        }
        .buttonStyle(.plain)
        .onHover { popover.setBadgeHover($0) }
        .onChange(of: popover.isPresented) { _, open in popover.handlePresentationChanged(open) }
        .onDisappear { popover.teardown() }
        .popover(isPresented: $popover.isPresented, arrowEdge: .bottom) {
            PerAppRulesPopover(entry: entry, availableInputSources: availableInputSources)
                .environmentObject(loc)
                .background(NSViewAnchor { popover.popoverNSView = $0 })
        }
        .accessibilityIdentifier("mapping.app_rules.\(triggerID)")
    }
}

/// Read-only popover listing a mapping's global default action alongside each
/// ordered per-app override rule (with real app icons and localized names).
private struct PerAppRulesPopover: View {
    let entry: ActionMappingEntry
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    @EnvironmentObject var loc: LocalizationManager

    private struct AppTag: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
        let excluded: Bool
    }

    private func appTags(for binding: MappingBinding) -> [AppTag]? {
        guard !binding.when.isEmpty else { return nil }
        var tags: [AppTag] = []
        for cond in binding.when {
            switch cond {
            case .frontmostApp(let include, let exclude):
                for bid in include {
                    let meta = AppMetadataCache.lookup(bid)
                    tags.append(AppTag(id: "in:\(bid)", name: meta.name, icon: meta.icon, excluded: false))
                }
                for bid in exclude {
                    let meta = AppMetadataCache.lookup(bid)
                    tags.append(AppTag(id: "ex:\(bid)", name: meta.name, icon: meta.icon, excluded: true))
                }
            case .unknown:
                return nil
            }
        }
        return tags.isEmpty ? nil : tags
    }

    var body: some View {
        let defaultDisplay = actionRefDisplay(entry.actionId, entry.inlineAction, loc,
                                              availableInputSources: availableInputSources)
        let defaultAccent: Color = {
            if defaultDisplay.invalid { return .orange }
            return ActionsRegistry.shared.resolve(entry).map(actionCategoryColor) ?? .secondary
        }()

        VStack(alignment: .leading, spacing: 9) {
            // Header: trigger keycaps + per-app rule count
            HStack(spacing: 8) {
                TriggerChips(trigger: entry.trigger, style: .raised)
                Spacer(minLength: 8)
                Text(loc.t("mappings.app_rules"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(entry.bindings.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }

            // Global default action row
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                Text(loc.t("mappings.default_action"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 10)
                ActionPill(display: defaultDisplay, accent: defaultAccent)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))

            Divider().opacity(0.55)

            // Per-app override rows
            if entry.bindings.count > 5 {
                ScrollView {
                    rulesList
                }
                .frame(maxHeight: 240)
            } else {
                rulesList
            }
        }
        .padding(12)
        .frame(width: 336)
        .accessibilityIdentifier("mapping.app_rules.popover")
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entry.bindings.enumerated()), id: \.offset) { idx, binding in
                if idx > 0 {
                    Divider().opacity(0.35)
                }
                ruleRow(binding)
            }
        }
    }

    private func ruleRow(_ binding: MappingBinding) -> some View {
        let display = actionRefDisplay(binding.actionId, binding.inlineAction, loc,
                                       availableInputSources: availableInputSources)
        let accent: Color = {
            if display.invalid { return .orange }
            return ActionsRegistry.shared.resolve(binding).map(actionCategoryColor) ?? .secondary
        }()

        return HStack(alignment: .center, spacing: 10) {
            if let tags = appTags(for: binding) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tags) { tag in
                        HStack(spacing: 6) {
                            if tag.excluded {
                                Text("≠")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.orange)
                            }
                            if let icon = tag.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            } else {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16, height: 16)
                            }
                            Text(tag.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            } else {
                Label(loc.t("mappings.advanced_rule"), systemImage: "curlybraces")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ActionPill(display: display, accent: accent)
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
    }
}

// MARK: - Inline Pill Meter (Slot ③)

/// Non-linear fill fraction in `0...1` for a mapping row's inline Pill Meter.
/// Uses `sqrt(count / maxCount)` so low-frequency mappings (e.g. 2 or 47 presses)
/// still render a visible liquid fill alongside a 10,000+ press navigation key,
/// while `count <= 0` returns `0` (empty fixed-width capsule slot).
func sparkBarFraction(count: Int, maxCount: Int) -> Double {
    guard count > 0, maxCount > 0 else { return 0 }
    let clamped = min(Double(count) / Double(maxCount), 1.0)
    return sqrt(clamped)
}

/// Non-linear liquid fill width in points (`0...pillWidth`) for `MappingSparkBar`.
func sparkBarFillWidth(count: Int, maxCount: Int,
                       pillWidth: CGFloat = MappingSparkBar.pillWidth,
                       minFillWidth: CGFloat = MappingSparkBar.minFillWidth) -> CGFloat {
    let frac = sparkBarFraction(count: count, maxCount: maxCount)
    guard frac > 0 else { return 0 }
    return min(pillWidth, max(minFillWidth, pillWidth * CGFloat(frac)))
}

/// Equal-height (`62pt × 23pt`) inline Pill Meter (Variant A: left-aligned category-
/// colored liquid fill + left-aligned tabular count) placed at the trailing edge of
/// every `MappingRow`. Matches the exact `23pt` height of the adjacent `ActionPill`
/// and locks every row's trailing slot to an identical fixed width so all
/// `ActionPill` trailing edges align along one vertical axis. Hovering the row or
/// pill brightens the category liquid, tints the `1pt` capsule rim, and raises the
/// count to full contrast — 100% self-contained with zero overhanging popovers.
struct MappingSparkBar: View {
    let count: Int
    let maxCount: Int
    var accent: Color = Self.defaultAccent
    var isRowHovered: Bool = false

    static let pillWidth: CGFloat = 62
    static let pillHeight: CGFloat = 23
    static let minFillWidth: CGFloat = 8
    static let leadingTextPadding: CGFloat = 8
    static let trailingTextPadding: CGFloat = 5
    static let defaultAccent = Color(red: 0.23, green: 0.61, blue: 1.00)

    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.colorScheme) private var scheme
    @State private var isPillHovered = false

    private var isHighlighted: Bool { isRowHovered || isPillHovered }

    private var accessibilityText: String {
        if count <= 0 { return loc.t("stats.spark_help_zero") }
        if count == 1 { return loc.t("stats.spark_help_one") }
        return loc.t("stats.spark_help", ["count": formatCount(count)])
    }

    var body: some View {
        let dark = scheme == .dark
        let hi = isHighlighted
        let fillW = sparkBarFillWidth(count: count, maxCount: maxCount)

        ZStack(alignment: .leading) {
            Capsule()
                .fill(dark ? Color.white.opacity(hi ? 0.075 : 0.06)
                           : Color.black.opacity(hi ? 0.055 : 0.045))

            if fillW > 0 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: dark
                                ? [accent.opacity(hi ? 0.52 : 0.36), accent.opacity(hi ? 0.38 : 0.25)]
                                : [accent.opacity(hi ? 0.44 : 0.29), accent.opacity(hi ? 0.30 : 0.20)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillW, height: Self.pillHeight)
            }

            Text(formatCount(max(0, count)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(
                    (dark ? Color(red: 0.96, green: 0.97, blue: 1.0)
                          : Color(red: 0.08, green: 0.09, blue: 0.12))
                        .opacity(numberOpacity(dark: dark, highlighted: hi))
                )
                .shadow(
                    color: count > 0
                        ? (dark ? Color.black.opacity(0.36) : Color.white.opacity(0.50))
                        : .clear,
                    radius: dark ? 1.0 : 0.5,
                    x: 0,
                    y: 0.5
                )
                .padding(.leading, Self.leadingTextPadding)
                .padding(.trailing, Self.trailingTextPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.pillWidth, height: Self.pillHeight)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    hi ? accent.opacity(dark ? 0.58 : 0.50)
                       : (dark ? Color.white.opacity(0.095) : Color.black.opacity(0.085)),
                    lineWidth: 1
                )
        )
        .shadow(
            color: hi ? accent.opacity(dark ? (count > 0 ? 0.24 : 0.12) : (count > 0 ? 0.16 : 0.08)) : .clear,
            radius: 4,
            x: 0,
            y: 0
        )
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isPillHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: hi)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.t("nav.statistics"))
        .accessibilityValue(accessibilityText)
    }

    private func numberOpacity(dark: Bool, highlighted: Bool) -> Double {
        if highlighted { return 1.0 }
        if count <= 0 { return dark ? 0.28 : 0.30 }
        return dark ? 0.56 : 0.58
    }
}

// MARK: - Shared mapping row

/// One mapping row: trigger keycaps on the left, and a clean 3-slot trailing
/// cluster (`PerAppRulesBadge` → solid `ActionPill` → fixed-width `MappingSparkBar`)
/// with zero permanent inline action buttons. Double-click edits; right-click opens
/// the native macOS context menu (`Edit…` / `Delete`).
struct MappingRow: View {
    let entry: ActionMappingEntry
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    var keycapStyle: KeycapStyle = .raised
    var usageCount: Int = 0
    var maxUsageCount: Int = 0
    var showInlineStats: Bool = true
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var loc: LocalizationManager
    @State private var isRowHovered = false

    var body: some View {
        let d = mappingActionDisplay(entry, loc, availableInputSources: availableInputSources)
        let accent = actionAccent(entry, invalid: d.invalid)
        let triggerID = triggerUniqueID(entry.trigger)
        // Explicit HStack (not LabeledContent) so the trigger sits left and the
        // action cluster sits right in EVERY context — LabeledContent only spreads
        // that way inside a Form; elsewhere (e.g. the keyboard style's Other
        // Triggers) it would center.
        return HStack(spacing: 8) {
            TriggerChips(trigger: entry.trigger, style: keycapStyle)
                .fixedSize()
            Spacer(minLength: 12)
            if !entry.bindings.isEmpty {
                PerAppRulesBadge(entry: entry, availableInputSources: availableInputSources)
                    .fixedSize()
            }
            ActionPill(display: d, accent: accent)
            if showInlineStats {
                MappingSparkBar(count: usageCount, maxCount: maxUsageCount,
                                accent: accent, isRowHovered: isRowHovered)
                    .fixedSize()
                    .accessibilityIdentifier("mapping.sparkbar.\(triggerID)")
            }
        }
        // Fill the row width so the Spacer actually spreads trigger-left /
        // action-right — needed outside a Form (Form rows already get full width).
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isRowHovered = hovering
        }
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button(action: onEdit) {
                Label(loc.t("mappings.edit_ellipsis"), systemImage: "pencil")
            }
            .accessibilityIdentifier("mapping.context.edit.\(triggerID)")
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label(loc.t("mappings.delete"), systemImage: "trash")
            }
            .accessibilityIdentifier("mapping.context.delete.\(triggerID)")
        }
        .accessibilityIdentifier("mapping.row.\(triggerID)")
    }
}

// MARK: - Style: Grouped by trigger

struct MappingsGroupedStyleView: View {
    let entries: [ActionMappingEntry]
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    var keycapStyle: KeycapStyle = .glass
    /// triggerID → all-time press count; empty when inline counts are disabled.
    var usageTotals: [String: Int] = [:]
    var maxUsageCount: Int = 0
    var showInlineStats: Bool = true
    let onEdit: (ActionMappingEntry) -> Void
    let onDelete: (ActionMappingEntry) -> Void
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        Form {
            if entries.isEmpty {
                Section { Text(loc.t("mappings.empty")).foregroundStyle(.secondary) }
            } else {
                // `entries` arrives pre-sorted by triggerSortKey; filtering per
                // category preserves that order. Empty categories are skipped.
                ForEach(TriggerCategory.allCases, id: \.self) { category in
                    let items = entries.filter { triggerCategory($0.trigger) == category }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.trigger) { entry in
                                MappingRow(entry: entry, availableInputSources: availableInputSources,
                                           keycapStyle: keycapStyle,
                                           usageCount: usageTotals[triggerUniqueID(entry.trigger)] ?? 0,
                                           maxUsageCount: maxUsageCount,
                                           showInlineStats: showInlineStats,
                                           onEdit: { onEdit(entry) }, onDelete: { onDelete(entry) })
                            }
                        } header: {
                            HStack(spacing: 7) {
                                Text(loc.t(category.nameKey))
                                Text("\(items.count)").foregroundStyle(.tertiary).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Style: Keyboard map

// `MappingsKeyboardStyleView` lives in MappingsKeyboardStyle.swift.
