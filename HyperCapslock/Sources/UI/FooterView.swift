import SwiftUI
import AppKit

struct AboutPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        PageScaffold(title: loc.t("nav.about")) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                Text("HyperCapslock")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(brandGradient)
                Text("\(loc.t("about.version")) \(app.appVersion)")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Text(loc.t("app.subtitle")).font(.system(size: 13)).foregroundColor(.secondary)

                Button { UpdaterManager.shared.checkForUpdates() } label: {
                    Text(loc.t("update.check")).frame(minWidth: 140)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(.blue)
                .padding(.top, 8)

                HStack(spacing: 20) {
                    linkButton(asset: "GitHubLogo", text: loc.t("footer.github"), url: "https://github.com/XueshiQiao/HyperCapslock")
                    linkButton(asset: "XLogo", text: "@XueshiQiao", url: "https://x.com/XueshiQiao")
                    linkButton(systemImage: "globe", text: "xueshi.dev", url: "https://xueshi.dev")
                }
                .padding(.top, 8)

                Text("\(loc.t("about.license"))  ·  \(loc.t("footer.more_apps_desc")) xueshi.dev")
                    .font(.system(size: 11)).foregroundColor(Color.secondary.opacity(0.7))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
    }

    private func linkButton(asset: String? = nil, systemImage: String? = nil, text: String, url: String) -> some View {
        Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: {
            HStack(spacing: 6) {
                if let asset { Image(asset).renderingMode(.template).resizable().frame(width: 15, height: 15) }
                else if let systemImage { Image(systemName: systemImage).font(.system(size: 14)) }
                Text(text).font(.system(size: 12.5))
            }
        }
        .buttonStyle(.plain).foregroundColor(.secondary)
    }
}
