import SwiftUI

/// Centralized look & feel for Lang Coach.
enum Theme {
    static let accent = Color(red: 0.30, green: 0.42, blue: 0.95)
    static let accentSoft = Color(red: 0.55, green: 0.45, blue: 0.98)
    static let success = Color(red: 0.20, green: 0.70, blue: 0.45)
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.18)
    static let danger = Color(red: 0.90, green: 0.30, blue: 0.35)

    static let brandGradient = LinearGradient(
        colors: [accent, accentSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let corner: CGFloat = 16
}

/// A soft, rounded surface used for cards and panels.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(padding: CGFloat = 20) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

/// A prominent, gradient-filled primary action button style.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                Theme.brandGradient.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// A reusable empty-state / call-to-action view.
struct CalloutView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.brandGradient)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// A small pill-shaped stat badge.
struct StatBadge: View {
    var value: String
    var label: String
    var tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
