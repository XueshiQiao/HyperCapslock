import SwiftUI

/// The HUD panel content. Ports `Hud.tsx`: a dark rounded panel showing the
/// trigger keycaps → arrow → action keycaps, with an optional caption.
struct HudView: View {
    @ObservedObject var model: HudViewModel

    private static let modWordToGlyph: [String: String] = [
        "Cmd": "⌘", "Ctrl": "⌃", "Option": "⌥", "Opt": "⌥", "Alt": "⌥", "Shift": "⇧",
    ]

    /// Split a trigger/combo string into keycap tokens (mirrors `tokenize`).
    private func tokenize(_ s: String) -> [String] {
        guard !s.isEmpty else { return [] }
        let parts = s.contains("+") ? s.split(separator: "+") : s.split(separator: " ")
        return parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Self.modWordToGlyph[$0] ?? $0 }
    }

    var body: some View {
        Group {
            if let payload = model.payload {
                panel(triggerKeys: tokenize(payload.trigger),
                      comboKeys: tokenize(payload.combo),
                      caption: payload.caption)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func panel(triggerKeys: [String], comboKeys: [String], caption: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                keycapGroup(triggerKeys, accent: false)
                arrow
                keycapGroup(comboKeys, accent: true)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(red: 0.65, green: 0.70, blue: 0.78))
                    .lineLimit(1)
                    .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(red: 0.066, green: 0.086, blue: 0.149).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 25, x: 0, y: 18)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keycapGroup(_ keys: [String], accent: Bool) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(keys.enumerated()), id: \.offset) { idx, key in
                if idx > 0 {
                    Text("+").foregroundColor(Color(red: 0.39, green: 0.45, blue: 0.55))
                        .font(.system(size: 14, weight: .semibold))
                }
                keycap(key, accent: accent)
            }
        }
    }

    private func keycap(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Color(red: 0.97, green: 0.98, blue: 0.99))
            .frame(minWidth: 40, minHeight: 40)
            .padding(.horizontal, 11)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: accent
                            ? [Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.26, green: 0.22, blue: 0.79)]
                            : [Color(red: 0.28, green: 0.34, blue: 0.41), Color(red: 0.20, green: 0.25, blue: 0.33), Color(red: 0.16, green: 0.21, blue: 0.28)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: accent ? Color(red: 0.31, green: 0.27, blue: 0.90).opacity(0.5) : .black.opacity(0.45),
                            radius: accent ? 7 : 5, x: 0, y: 4)
            )
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(Color(red: 0.49, green: 0.54, blue: 0.63))
            .frame(width: 46, height: 22)
    }
}
