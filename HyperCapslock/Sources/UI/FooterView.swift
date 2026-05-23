import SwiftUI
import AppKit

struct FooterView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                linkButton(systemImage: "chevron.left.forwardslash.chevron.right",
                           help: loc.t("footer.github"),
                           url: "https://github.com/XueshiQiao/HyperCapslock")
                Text("v\(app.appVersion)").font(.system(size: 11)).foregroundColor(.secondary)
                Circle().fill(Color.secondary.opacity(0.4)).frame(width: 3, height: 3)
                Text(loc.t("footer.by")).font(.system(size: 11)).foregroundColor(.secondary)
                Button("@XueshiQiao") { open("https://x.com/XueshiQiao") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Text(loc.t("footer.more_apps_desc")).font(.system(size: 11)).foregroundColor(.secondary)
                Button("xueshi.dev") { open("https://xueshi.dev") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.blue)
            }
            Button(loc.t("update.check")) { UpdaterManager.shared.checkForUpdates() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.blue)
        }
        .padding(.top, 4).padding(.bottom, 8)
    }

    private func linkButton(systemImage: String, help: String, url: String) -> some View {
        Button { open(url) } label: { Image(systemName: systemImage) }
            .buttonStyle(.plain).foregroundColor(.secondary).help(help)
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
