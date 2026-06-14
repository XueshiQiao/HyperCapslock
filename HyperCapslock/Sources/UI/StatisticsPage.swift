import SwiftUI
import AppKit

// The Statistics page: how many times each mapping (trigger) has fired. Reuses
// the Mappings page's `TriggerChips` / `ActionPill` / category colors so a row
// reads identically to a mapping row — just with a usage bar + count instead of
// the edit/delete affordances. Data comes from `UsageStats` (per-day buckets),
// summed over the selected range.

// MARK: - Shared count helpers (also used by the Mappings-page inline badge)

/// Locale-grouped count string (e.g. "1,234").
func formatCount(_ n: Int) -> String { n.formatted() }

/// Subtle inline press-count badge shown on a Mappings row when the
/// `stats_show_inline` setting is on.
struct UsageCountBadge: View {
    let count: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "hand.tap.fill").font(.system(size: 9))
            Text(formatCount(count)).font(.caption2).monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}

/// Reconstruct a `Trigger` from its `triggerUniqueID` string. Lets the page show
/// triggers that still carry a count but whose mapping was deleted. Returns nil
/// for an unparseable id (corrupted data) — the caller then shows the raw id.
func triggerFromUniqueID(_ id: String) -> Trigger? {
    switch id {
    case "single_tap_hyper": return .singleTapHyper
    case "double_tap_hyper": return .doubleTapHyper
    default:
        if id.hasPrefix("dtm:") {
            guard let m = ModifierKey(rawValue: String(id.dropFirst(4))) else { return nil }
            return .doubleTapModifier(m)
        }
        if id.hasPrefix("hyper:") {
            let parts = id.split(separator: ":")
            guard parts.count == 3, let key = UInt16(parts[1]) else { return nil }
            return .hyperPlusKey(key: key, withShift: parts[2] == "s")
        }
        return nil
    }
}

// MARK: - Usage bar

/// A horizontal proportional bar tinted in the action's category color.
private struct UsageBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.62)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, g.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Stat row

private struct StatRow: View {
    let triggerID: String
    let entry: ActionMappingEntry?
    let count: Int
    let fraction: Double
    let availableInputSources: [String: InputSourceFix.AvailableSource]
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        let trigger = entry?.trigger ?? triggerFromUniqueID(triggerID)
        let display = entry.map { mappingActionDisplay($0, loc, availableInputSources: availableInputSources) }
        let accent: Color = {
            if let entry, let display { return actionAccent(entry, invalid: display.invalid) }
            return .secondary
        }()

        return HStack(spacing: 10) {
            if let trigger {
                TriggerChips(trigger: trigger, style: .glass)
            } else {
                Text(triggerID).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let display {
                ActionPill(display: display, accent: accent)
            } else {
                Text(loc.t("stats.removed"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            if let entry, !entry.bindings.isEmpty {
                PerAppRulesBadge(bindings: entry.bindings)
            }
            Spacer(minLength: 8)
            UsageBar(fraction: fraction, color: accent).frame(width: 84)
            Text(formatCount(count))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit().foregroundStyle(.primary)
                .frame(minWidth: 54, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Page

struct StatisticsPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    @State private var range: StatsRange = .all
    @State private var totals: [String: Int] = [:]
    @State private var hasAny = false
    @State private var showResetConfirm = false
    @State private var availableInputSources: [String: InputSourceFix.AvailableSource] = InputSourceFix.availableSourcesByID()

    /// Triggers with a non-zero count, highest first (id as a stable tiebreak).
    private var ranked: [(id: String, count: Int)] {
        totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
              .map { (id: $0.key, count: $0.value) }
    }
    private var grandTotal: Int { totals.values.reduce(0, +) }
    private var maxCount: Int { ranked.first?.count ?? 0 }
    private var entriesByID: [String: ActionMappingEntry] {
        Dictionary(config.mappings.map { (triggerUniqueID($0.trigger), $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func refresh() {
        let new = UsageStats.shared.totals(in: range)
        if new != totals { totals = new }
        let any = UsageStats.shared.hasAnyData()
        if any != hasAny { hasAny = any }
    }

    var body: some View {
        Form {
            Section {
                Picker("", selection: $range) {
                    Text(loc.t("stats.range.today")).tag(StatsRange.today)
                    Text(loc.t("stats.range.7d")).tag(StatsRange.last7)
                    Text(loc.t("stats.range.30d")).tag(StatsRange.last30)
                    Text(loc.t("stats.range.all")).tag(StatsRange.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("stats.range")
            }

            Section {
                HStack(spacing: 10) {
                    IconTile(symbol: "hand.tap.fill", color: .purple)
                    Text(loc.t("stats.total_label"))
                    Spacer()
                    Text(formatCount(grandTotal))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.primary)
                        .accessibilityIdentifier("stats.total")
                }
            } footer: {
                Text(loc.t("stats.page_hint")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if ranked.isEmpty {
                    emptyState
                } else {
                    ForEach(ranked, id: \.id) { item in
                        StatRow(triggerID: item.id,
                                entry: entriesByID[item.id],
                                count: item.count,
                                fraction: maxCount > 0 ? Double(item.count) / Double(maxCount) : 0,
                                availableInputSources: availableInputSources)
                            .accessibilityIdentifier("stats.row.\(item.id)")
                    }
                }
            } header: {
                Text(loc.t("stats.ranking"))
            }

            Section {
                Button(role: .destructive) { showResetConfirm = true } label: {
                    HStack(spacing: 10) {
                        IconTile(symbol: "trash", color: .red)
                        Text(loc.t("stats.reset"))
                    }
                }
                .accessibilityIdentifier("stats.reset")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.statistics"))
        .onAppear {
            availableInputSources = InputSourceFix.refreshAvailableSourcesByID()
            refresh()
        }
        // Live refresh while the page is visible (and an immediate refresh when
        // the range changes). The task is cancelled when the page goes away, so
        // an idle page does no work; unchanged totals don't re-render (guarded).
        .task(id: range) {
            refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { break }
                refresh()
            }
        }
        .confirmationDialog(loc.t("stats.reset_title"), isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button(loc.t("stats.reset_ok"), role: .destructive) {
                UsageStats.shared.reset()
                refresh()
                app.showToast(loc.t("toast.stats_reset"))
            }
            Button(loc.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("stats.reset_msg"))
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text(hasAny ? loc.t("stats.empty") : loc.t("stats.empty_all"))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.vertical, 22)
    }
}
