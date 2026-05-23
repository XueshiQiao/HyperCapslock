import SwiftUI
import AppKit

struct FooterView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { open("https://github.com/XueshiQiao/HyperCapslock") } label: {
                    Image("GitHubLogo").renderingMode(.template).resizable()
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain).foregroundColor(.secondary).help(loc.t("footer.github"))

                Text("v\(app.appVersion)").font(.system(size: 11)).foregroundColor(.secondary)
                Circle().fill(Color.secondary.opacity(0.4)).frame(width: 3, height: 3)
                Text(loc.t("footer.by")).font(.system(size: 11)).foregroundColor(.secondary)

                Button { open("https://x.com/XueshiQiao") } label: {
                    HStack(spacing: 4) {
                        Image("XLogo").renderingMode(.template).resizable()
                            .frame(width: 11, height: 11)
                        Text("@XueshiQiao").font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain).foregroundColor(.secondary).help("@XueshiQiao on X")
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

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
