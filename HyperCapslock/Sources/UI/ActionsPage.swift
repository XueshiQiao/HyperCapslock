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
        Form {
            Section(loc.t("actions.custom")) {
                if config.customActions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(.orange.opacity(0.7))
                        Text(loc.t("actions.none_custom"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(config.customActions) { action in actionRow(action, editable: true) }
                }
            }
            Section {
                ForEach(BuiltinActions.all) { action in actionRow(action, editable: false) }
            } header: {
                Text(loc.t("actions.builtin"))
            } footer: {
                Text(loc.t("actions.builtin_hint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.actions"))
        .toolbar {
            ToolbarItem {
                Button { sheet = .add } label: { Image(systemName: "plus") }.help(loc.t("actions.add"))
            }
        }
        .sheet(item: $sheet) { mode in
            AddEditActionView(mode: mode).environmentObject(app).environmentObject(config).environmentObject(loc)
        }
    }

    private func actionRow(_ action: Action, editable: Bool) -> some View {
        let name = action.nameKey.map { loc.t($0) } ?? action.name
        let desc = actionPresentation(action.config, loc).value
        let refCount = config.mappingsReferencing(actionId: action.id).count
        return LabeledContent {
            HStack(spacing: 10) {
                if refCount > 0 {
                    Text(loc.t("actions.used_by", ["count": String(refCount)]))
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                if editable {
                    Button { sheet = .edit(action) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    Button { delete(action) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                } else {
                    Image(systemName: actionSymbol(action.config)).foregroundStyle(.secondary)
                }
            }
        } label: {
            if editable && name != desc {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(name)   // built-ins: one line (name == description)
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
