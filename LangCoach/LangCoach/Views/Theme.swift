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
    static let cornerLarge: CGFloat = 22
}

/// A soft, warm backdrop for the practice screens: the standard window
/// background lifted by a faint brand-tinted glow at the top. Adaptive to
/// light/dark since it only layers low-opacity accent over the system fill.
struct PracticeBackground: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay(alignment: .top) {
                Theme.brandGradient
                    .opacity(0.07)
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .blur(radius: 70)
                    .offset(y: -60)
            }
            .ignoresSafeArea()
    }
}

/// A gradient-filled, app-style rounded icon tile with a soft brand shadow.
/// The shared building block for heros, empty states, and pane headers.
struct IconTile: View {
    var systemImage: String
    var size: CGFloat = 44
    /// When true, adds a diffuse glow halo behind the tile (for large hero uses).
    var glow: Bool = false

    var body: some View {
        ZStack {
            if glow {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: size * 1.3, height: size * 1.3)
                    .opacity(0.18)
                    .blur(radius: size * 0.19)
            }
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: size, height: size)
                .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.22, y: size * 0.11)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

/// The friendly hero used at the top of each practice setup screen: a
/// gradient-filled app-style icon tile with a soft glow, a rounded title,
/// and a supporting line.
struct SetupHero: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            IconTile(systemImage: systemImage, size: 74, glow: true)
            Text(title)
                .font(.system(.title, design: .rounded).weight(.bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 420)
        }
    }
}

/// A compact pane header: a small gradient icon tile beside a rounded title and
/// optional subtitle. Used at the top of the Library and Flashcards detail panes.
struct PaneHeader<Trailing: View>: View {
    var systemImage: String
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// A small uppercase section label for grouped form rows.
struct FieldLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

/// A custom capsule "segmented" control with a gradient thumb that glides
/// between options — friendlier and more animated than `.pickerStyle(.segmented)`.
struct PillPicker<T: Hashable>: View {
    var items: [T]
    @Binding var selection: T
    var label: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Text(label(item))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.brandGradient)
                                .matchedGeometryEffect(id: "pillThumb", in: ns)
                                .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                            selection = item
                        }
                    }
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.05), lineWidth: 1))
    }
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
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
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
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                Theme.brandGradient.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: Theme.accent.opacity(isEnabled ? 0.3 : 0), radius: 12, y: 5)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            IconTile(systemImage: systemImage, size: 64, glow: true)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// A simple wrapping layout: lays subviews left-to-right and wraps to the next
/// line when they run out of width. Used for variable-width theme chips/pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, offset) in arrange(subviews, maxWidth: bounds.width).offsets {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, offsets: [(Int, CGPoint)]) {
        var offsets: [(Int, CGPoint)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append((index, CGPoint(x: x, y: y)))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: widest, height: y + rowHeight), offsets)
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
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 66)
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(tint.opacity(0.14), lineWidth: 1))
    }
}
