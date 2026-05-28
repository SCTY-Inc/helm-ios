import SwiftUI

/// A small status dot used in list rows to convey reachability at a glance
/// without coloring entire icons. Green = healthy, amber = partial, red =
/// unreachable, gray = idle/unchecked.
struct StatusDot: View {
    enum Level {
        case online
        case partial
        case offline
        case idle

        var color: Color {
            switch self {
            case .online: .green
            case .partial: .orange
            case .offline: .red
            case .idle: Color.secondary.opacity(0.4)
            }
        }
    }

    let level: Level
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .stroke(level.color.opacity(level == .idle ? 0 : 0.25), lineWidth: 3)
                    .scaleEffect(1.6)
            )
            .accessibilityHidden(true)
    }
}

extension View {
    /// Standard inset for Helm list rows.
    func helmRowInsets() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
    }
}
