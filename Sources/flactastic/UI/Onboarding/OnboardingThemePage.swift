import SwiftUI

struct OnboardingThemePage: View {
    @Environment(Settings.self) private var settings
    @Namespace private var selectionAnim

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Text("Choose your appearance")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)
                .riseFadeIn(delay: 0.0)

            HStack(spacing: Theme.Spacing.xl) {
                ThemePreviewTile(
                    title: "Dark",
                    isLight: false,
                    isSelected: !settings.useLightMode,
                    namespace: selectionAnim
                ) {
                    select(light: false)
                }
                .riseFadeIn(delay: 0.08)

                ThemePreviewTile(
                    title: "Light",
                    isLight: true,
                    isSelected: settings.useLightMode,
                    namespace: selectionAnim
                ) {
                    select(light: true)
                }
                .riseFadeIn(delay: 0.14)
            }

            Button(action: onContinue) {
                Text("Continue to FLACtastic")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(
                        Capsule().fill(Theme.accent)
                    )
            }
            .buttonStyle(.plain)
            .riseFadeIn(delay: 0.22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }

    private func select(light: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) {
            settings.useLightMode = light
        }
    }
}

private struct ThemePreviewTile: View {
    let title: String
    let isLight: Bool
    let isSelected: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            previewCard
                .frame(width: 220, height: 150)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                )
                .overlay(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                .stroke(Theme.accent, lineWidth: 2.5)
                                .matchedGeometryEffect(id: "themeSelection", in: namespace)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)

            Text(title)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var bg: Color {
        isLight ? Color(white: 0.96) : Color.black
    }

    private var surface: Color {
        isLight ? Color(white: 0.84) : Color(white: 0.12)
    }

    private var primaryText: Color {
        isLight ? Color(white: 0.08) : Color(white: 0.95)
    }

    private var secondaryText: Color {
        isLight ? Color(white: 0.45) : Color(white: 0.55)
    }

    private var accent: Color {
        isLight ? Color.black : Color.white
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 6, height: 6)
                Circle().fill(Color.yellow.opacity(0.7)).frame(width: 6, height: 6)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 6, height: 6)
                Spacer()
            }

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(surface)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(primaryText)
                        .frame(width: 90, height: 6)
                    RoundedRectangle(cornerRadius: 2).fill(secondaryText)
                        .frame(width: 60, height: 5)
                }
                Spacer()
            }

            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(secondaryText.opacity(0.6))
                        .frame(width: 80, height: 5)
                    Spacer()
                    RoundedRectangle(cornerRadius: 2).fill(secondaryText.opacity(0.4))
                        .frame(width: 24, height: 5)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Capsule().fill(accent)
                    .frame(width: 60, height: 14)
                Spacer()
            }
        }
        .padding(12)
    }
}
