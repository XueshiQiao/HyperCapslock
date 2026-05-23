import SwiftUI

enum ActionSheetMode: Identifiable {
    case add
    case edit(Action)
    var id: String { switch self { case .add: return "add"; case .edit(let a): return "edit-\(a.id)" } }
}

struct ActionsPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager
    @State private var sheet: ActionSheetMode?

    var body: some View {
        PageScaffold(title: loc.t("nav.actions"), trailing: AnyView(
            Button { sheet = .add } label: { Label(loc.t("actions.add"), systemImage: "plus") }
                .controlSize(.small).buttonStyle(.borderedProminent))) {

            // Custom actions
            SettingsSection(title: loc.t("actions.custom")) {
                if config.customActions.isEmpty {
                    SettingsRow(label: loc.t("actions.none_custom"), isFirst: true) { EmptyView() }
                } else {
                    ForEach(Array(config.customActions.enumerated()), id: \.element.id) { idx, action in
                        actionRow(action, isFirst: idx == 0, editable: true)
                    }
                }
            }

            // Built-in actions (read-only)
            SettingsSection(title: loc.t("actions.builtin")) {
                ForEach(Array(BuiltinActions.all.enumerated()), id: \.element.id) { idx, action in
                    actionRow(action, isFirst: idx == 0, editable: false)
                }
            }
            Text(loc.t("actions.builtin_hint")).font(.system(size: 11)).foregroundColor(.secondary).padding(.horizontal, 4)
        }
        .sheet(item: $sheet) { mode in
            AddEditActionView(mode: mode)
                .environmentObject(app).environmentObject(config).environmentObject(loc)
        }
    }

    private func actionRow(_ action: Action, isFirst: Bool, editable: Bool) -> some View {
        let name = action.nameKey.map { loc.t($0) } ?? action.name
        let desc = actionPresentation(action.config, loc).value
        let refCount = config.mappingsReferencing(actionId: action.id).count
        // Only show the description line when it adds info (custom actions);
        // for built-ins the name and description are identical → one line.
        return SettingsRow(label: name, sublabel: name == desc ? nil : desc, isFirst: isFirst) {
            HStack(spacing: 10) {
                Image(systemName: actionSymbol(action.config)).font(.system(size: 12)).foregroundColor(.accentColor)
                if refCount > 0 {
                    Text(loc.t("actions.used_by", ["count": String(refCount)]))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                if editable {
                    Button { sheet = .edit(action) } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundColor(.secondary)
                    Button { delete(action) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundColor(.secondary)
                }
            }
        }
    }

    private func delete(_ action: Action) {
        do {
            try app.removeCustomAction(id: action.id)
            app.showToast(loc.t("toast.action_removed"))
        } catch {
            if case ConfigError.actionInUse(let triggers) = error {
                app.showToast(loc.t("actions.delete_blocked", ["triggers": triggers]), isError: true)
            } else {
                app.showToast(loc.t("toast.action_remove_failed"), isError: true)
            }
        }
    }
}
