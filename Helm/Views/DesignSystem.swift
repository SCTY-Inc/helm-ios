import SwiftUI

struct HelmSymbolBadge: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.1), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct HelmPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

extension View {
    /// Standard inset for Helm list rows.
    func helmRowInsets() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
    }
}
