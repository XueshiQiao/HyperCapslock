import SwiftUI
import AppKit

struct AboutPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19))
                    Text("HyperCapslock").font(.title2).fontWeight(.bold)
                    Text("\(loc.t("about.version")) \(app.appVersion)").font(.callout).foregroundStyle(.secondary)
                    Text(loc.t("app.subtitle")).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section(loc.t("about.links")) {
                linkRow(asset: "GitHubLogo", title: loc.t("footer.github"), url: "https://github.com/XueshiQiao/HyperCapslock")
                linkRow(asset: "XLogo", title: "@XueshiQiao", url: "https://x.com/XueshiQiao")
                linkRow(systemImage: "globe", title: "\(loc.t("footer.more_apps_desc")) xueshi.dev", url: "https://xueshi.dev")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.about"))
        .toolbar {
            ToolbarItem {
                Button { UpdaterManager.shared.checkForUpdates() } label: {
                    Label(loc.t("update.check"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    private func linkRow(asset: String? = nil, systemImage: String? = nil, title: String, url: String) -> some View {
        Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: {
            HStack(spacing: 9) {
                if let asset { Image(asset).renderingMode(.template).resizable().frame(width: 15, height: 15) }
                else if let systemImage { Image(systemName: systemImage) }
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
