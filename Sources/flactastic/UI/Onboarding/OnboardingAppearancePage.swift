import SwiftUI

struct OnboardingAppearancePage: View {
    @Environment(Settings.self) private var settings
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            OnboardingStepHeader(
                step: 1, total: 3,
                title: "Choose your look",
                subtitle: "You can change this later in Settings."
            )
            .riseFadeIn(delay: 0.0)

            HStack(spacing: Theme.Spacing.md) {
                AppearanceTile(title: "Dark", isLight: false, isSelected: !settings.useLightMode) {
                    select(light: false)
                }
                AppearanceTile(title: "Light", isLight: true, isSelected: settings.useLightMode) {
                    select(light: true)
                }
            }
            .riseFadeIn(delay: 0.08)

            Button("Continue", action: onNext)
                .onboardingPrimaryButton()
                .riseFadeIn(delay: 0.14)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func select(light: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            settings.useLightMode = light
        }
    }
}

/// A selectable Dark/Light preview card: a small mock-UI swatch above a
/// title + selection indicator row.
private struct AppearanceTile: View {
    let title: String
    let isLight: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                swatch
                HStack {
                    Text(title)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    selectionMark
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(isSelected ? Theme.textPrimary : Theme.divider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isLight ? Color(white: 0.96) : Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isLight ? Color(white: 0.8) : Color(white: 0.18), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(isLight ? Color(white: 0.08) : Color(white: 0.95))
                        .frame(width: 42, height: 5)
                    Capsule().fill(isLight ? Color(white: 0.55) : Color(white: 0.45))
                        .frame(width: 26, height: 5)
                }
                .padding(10)
            }
            .frame(height: 64)
    }

    private var selectionMark: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Theme.accent : Color.clear)
            Circle()
                .strokeBorder(isSelected ? Theme.accent : Theme.divider, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.background)
            }
        }
        .frame(width: 16, height: 16)
    }
}
