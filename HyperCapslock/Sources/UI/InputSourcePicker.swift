import SwiftUI

/// A Picker over the currently-available input sources (icon + localized name),
/// bound to the selected source's plain `inputSourceID`. Shared by the action
/// editor and the mapping editor's "Switch Input Source" entries.
///
/// A stored id that's no longer installed is preserved as a selectable
/// "⚠️ <id> (unavailable)" row, so editing a mapping for a removed source never
/// silently drops it.
struct InputSourcePicker: View {
    @EnvironmentObject var loc: LocalizationManager
    let title: String
    @Binding var sourceID: String
    /// When true and nothing is selected yet, default to the first source so the
    /// picker isn't blank and the caller has a valid value.
    var defaultsToFirst: Bool = true

    @State private var sources: [InputSourceFix.AvailableSource] = []

    var body: some View {
        Picker(title, selection: $sourceID) {
            if !sourceID.isEmpty, !sources.contains(where: { $0.id == sourceID }) {
                Label("\(sourceID) \(loc.t("is.source_unavailable_suffix"))",
                      systemImage: "exclamationmark.triangle.fill")
                    .tag(sourceID)
            }
            ForEach(sources) { src in
                HStack(spacing: 6) {
                    if let icon = src.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(src.name)
                }
                .tag(src.id)
            }
        }
        .onAppear {
            sources = InputSourceFix.availableSources()
            if defaultsToFirst, sourceID.isEmpty { sourceID = sources.first?.id ?? "" }
        }
    }
}
