import SwiftUI

enum MappingSheetMode: Identifiable {
    case add
    case edit(ActionMappingEntry)
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let e): return "edit-\(triggerUniqueID(e.trigger))"
        }
    }
}

func triggerUniqueID(_ t: Trigger) -> String {
    switch t {
    case .singleTapHyper: return "single_tap_hyper"
    case .doubleTapHyper: return "double_tap_hyper"
    case .doubleTapModifier(let m): return "dtm:\(m.rawValue)"
    case .hyperPlusKey(let key, let withShift): return "hyper:\(key):\(withShift ? "s" : "n")"
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var config: ConfigStore
    @EnvironmentObject var loc: LocalizationManager

    @State private var sheet: MappingSheetMode?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    HStack(alignment: .top, spacing: 12) {
                        StatusCard()
                        SettingsCard()
                    }
                    PermissionsCard()
                    MappingsCard(sheet: $sheet)
                    FooterView()
                }
                .padding(24)
                .padding(.top, 8)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }

            topRightControls
                .padding(.top, 8)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let toast = app.toast {
                toastView(toast)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 560, minHeight: 600)
        .preferredColorScheme(app.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.2), value: app.toast)
        .sheet(item: $sheet) { mode in
            AddEditMappingView(mode: mode)
                .environmentObject(app)
                .environmentObject(config)
                .environmentObject(loc)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("HyperCapslock")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
            Text(loc.t("app.subtitle"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.top, 12)
    }

    private var topRightControls: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(AppLocale.allCases, id: \.self) { l in
                    Button { app.loc.setLocale(l) } label: {
                        Text("\(l.flag)  \(l.label)")
                    }
                }
            } label: {
                Text(loc.locale.flag)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)

            Button {
                app.setDark(!app.isDark)
            } label: {
                Image(systemName: app.isDark ? "sun.max" : "moon")
            }
            .buttonStyle(.borderless)
            .help(app.isDark ? loc.t("theme.light") : loc.t("theme.dark"))
        }
    }

    private func toastView(_ toast: AppState.ToastMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(toast.isError ? .red : .green)
            Text(toast.text).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke((toast.isError ? Color.red : Color.green).opacity(0.5), lineWidth: 1))
        .shadow(radius: 12, y: 4)
    }
}
