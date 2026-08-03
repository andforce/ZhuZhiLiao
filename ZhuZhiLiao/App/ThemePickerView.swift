import SwiftUI

struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let themeStore: SeasonThemeStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("四时之景")
                        .font(.custom("Songti SC", size: 27, relativeTo: .title2))

                    Text("选择属于此刻的竹知了")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成", action: dismiss.callAsFunction)
                    .font(.subheadline.weight(.semibold))
            }

            SeasonalGlassGroup(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SeasonTheme.allCases) { theme in
                        ThemePreviewCard(
                            theme: theme,
                            isSelected: themeStore.selectedTheme == theme,
                            action: { select(theme) }
                        )
                    }
                }
            }

            Text("主题会同时改变天空、季节意象、竹知了光泽与运动轨迹。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .sensoryFeedback(.selection, trigger: themeStore.selectedTheme)
    }

    private func select(_ theme: SeasonTheme) {
        withAnimation(.snappy(duration: 0.35)) {
            themeStore.select(theme)
        }
    }
}

private struct ThemePreviewCard: View {
    let theme: SeasonTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ThemeMiniature(theme: theme)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.fullName)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)

                        Text(theme.tagline)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.colors.accent : .white.opacity(0.32))
                }
            }
            .padding(11)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .seasonalGlass(theme: theme, cornerRadius: 20, interactive: true)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.colors.accent.opacity(0.82), lineWidth: 1.5)
            }
        }
        .accessibilityLabel("\(theme.fullName)，\(theme.tagline)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThemeMiniature: View {
    let theme: SeasonTheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.colors.skyTop, theme.colors.skyBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(theme.colors.highlight.opacity(0.88))
                .frame(width: 32, height: 32)
                .blur(radius: 0.4)
                .offset(x: 42, y: -22)

            Image(systemName: theme.symbolName)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.colors.accent.opacity(0.86))
                .shadow(color: theme.colors.accent.opacity(0.45), radius: 10)

            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? theme.colors.accent : theme.colors.highlight)
                    .frame(width: index.isMultiple(of: 3) ? 3 : 2)
                    .offset(
                        x: CGFloat((index * 31) % 112) - 56,
                        y: CGFloat((index * 23) % 64) - 32
                    )
                    .opacity(0.68)
            }
        }
        .frame(height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}

#Preview("四季选择器") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ThemePickerView(themeStore: SeasonThemeStore())
        }
}
