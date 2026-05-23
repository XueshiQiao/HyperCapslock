import SwiftUI

struct PermissionsCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    @State private var expanded = false
    @State private var didInit = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.t("perm.label").uppercased())
                                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                            Text(loc.t("perm.title")).font(.system(size: 13, weight: .medium))
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(spacing: 8) {
                        permissionRow(label: loc.t("perm.accessibility"), granted: app.accessibilityGranted, pane: .accessibility)
                        permissionRow(label: loc.t("perm.input_monitoring"), granted: app.inputMonitoringGranted, pane: .inputMonitoring)
                    }
                    HStack {
                        Text(loc.t("perm.macos_hint"))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Button(loc.t("perm.refresh")) {
                            app.refreshPermissions()
                            app.showToast(loc.t("toast.perm_refreshed"))
                        }
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            expanded = !(app.accessibilityGranted && app.inputMonitoringGranted)
        }
    }

    private func permissionRow(label: String, granted: Bool, pane: Permissions.Pane) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            if granted {
                badge(loc.t("perm.granted"), color: .green, clickable: false)
            } else {
                Button { Permissions.openPrivacyPane(pane) } label: {
                    HStack(spacing: 4) {
                        Text(loc.t("perm.not_granted"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.plain)
                .help("\(loc.t("perm.open_settings")) — \(label)")
                .modifier(BadgeStyle(color: .red))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func badge(_ text: String, color: Color, clickable: Bool) -> some View {
        Text(text).modifier(BadgeStyle(color: color))
    }
}

private struct BadgeStyle: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.15)))
    }
}
