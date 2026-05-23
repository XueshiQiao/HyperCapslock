import SwiftUI

/// A labelled settings section: small uppercase header + a rounded card body.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 4)
            Card { VStack(spacing: 0) { content } }
        }
    }
}

/// One row inside a settings card.
struct SettingsRow<Trailing: View>: View {
    let label: String
    var sublabel: String? = nil
    var isFirst: Bool = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            if !isFirst { Divider() }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13, weight: .medium))
                    if let sublabel { Text(sublabel).font(.system(size: 11)).foregroundColor(.secondary) }
                }
                Spacer()
                trailing
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }
}

/// Accessibility permission row (the only TCC gate for an active CGEventTap).
struct PermissionsSection: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    var body: some View {
        SettingsSection(title: loc.t("perm.label")) {
            SettingsRow(label: loc.t("perm.accessibility"),
                        sublabel: loc.t("perm.macos_hint"), isFirst: true) {
                if app.accessibilityGranted {
                    Text(loc.t("perm.granted")).modifier(BadgeStyle(color: .green))
                } else {
                    Button {
                        Permissions.promptAccessibility()
                        Permissions.openPrivacyPane(.accessibility)
                    } label: {
                        HStack(spacing: 4) { Text(loc.t("perm.not_granted")); Image(systemName: "arrow.right") }
                    }
                    .buttonStyle(.plain).modifier(BadgeStyle(color: .red))
                }
            }
            SettingsRow(label: loc.t("perm.refresh_label")) {
                Button(loc.t("perm.refresh")) {
                    app.refreshPermissions()
                    app.showToast(loc.t("toast.perm_refreshed"))
                }.controlSize(.small)
            }
        }
    }
}

struct BadgeStyle: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.15)))
    }
}
