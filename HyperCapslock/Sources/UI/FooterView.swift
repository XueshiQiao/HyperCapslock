import SwiftUI
import AppKit
import MoreAppsKit

struct AboutPage: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocalizationManager
    @State private var updateSpin = 0

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("BrandMascot")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: 98)
                        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
                        .accessibilityIdentifier("about.logo")
                    VStack(spacing: 4) {
                        Text("HyperCapslock").font(.title2).fontWeight(.bold)
                        Text(loc.t("about.tagline"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("about.tagline")
                    }
                    Text("\(loc.t("about.version")) \(app.appVersion) · \(loc.t("app.subtitle"))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section(loc.t("about.links")) {
                linkRow(asset: "GitHubLogo", tint: Color(red: 0.16, green: 0.17, blue: 0.20), title: loc.t("footer.github"), url: "https://github.com/XueshiQiao/HyperCapslock")
                linkRow(asset: "XLogo", tint: Color(red: 0.16, green: 0.17, blue: 0.20), title: "@XueshiQiao", url: "https://x.com/XueshiQiao")
            }

            // One row leading to the More Apps page (icons of the author's
            // other apps, how many there are, a chevron).
            Section {
                MoreAppsEntryRow(store: app.moreApps, title: loc.t("nav.more_apps")) {
                    IconTile(symbol: SidebarPage.moreAppsSymbol, color: SidebarPage.moreAppsColor)
                } action: {
                    app.showMoreApps(from: "about")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.t("nav.about"))
        .toolbar {
            ToolbarItem {
                Button {
                    updateSpin += 1
                    UpdaterManager.shared.checkForUpdates()
                } label: {
                    // Spin the circular-arrows symbol once per click (macOS 15+).
                    if #available(macOS 15, *) {
                        Label(loc.t("update.check"), systemImage: "arrow.triangle.2.circlepath")
                            .symbolEffect(.rotate, value: updateSpin)
                    } else {
                        Label(loc.t("update.check"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }

    private func linkRow(asset: String? = nil, systemImage: String? = nil, tint: Color, title: String, url: String) -> some View {
        Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: {
            HStack(spacing: 10) {
                if let asset { AssetIconTile(asset: asset, color: tint) }
                else if let systemImage { IconTile(symbol: systemImage, color: tint) }
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
