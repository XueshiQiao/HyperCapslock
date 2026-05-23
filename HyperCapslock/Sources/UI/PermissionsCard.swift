import SwiftUI

/// A small status pill (e.g. "Granted" / "Not Granted").
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
