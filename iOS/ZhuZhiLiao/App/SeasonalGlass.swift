import SwiftUI

struct SeasonalGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func seasonalGlass(
        theme: SeasonTheme,
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        modifier(
            SeasonalGlassModifier(
                theme: theme,
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }
}

private struct SeasonalGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let theme: SeasonTheme
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    theme.colors.panel.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(border)
        } else if #available(iOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(
                        .regular.tint(theme.colors.accent.opacity(0.10)).interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                content
                    .glassEffect(
                        .regular.tint(theme.colors.panel.opacity(0.12)),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            }
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .background(
                    theme.colors.panel.opacity(0.34),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(border)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.white.opacity(0.14), lineWidth: 0.75)
    }
}
