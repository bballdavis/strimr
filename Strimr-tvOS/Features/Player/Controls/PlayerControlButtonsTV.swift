import SwiftUI

struct PlayerIconButton: View {
    let systemName: String
    var accessibilityLabel: String?
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 22, style: .continuous)
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(chrome.fill(.thinMaterial))
                .overlay(
                    chrome.stroke(
                        Color.brandPrimary.opacity(isFocused ? 1.0 : 0.42),
                        lineWidth: isFocused ? 2 : 1
                    )
                )
                .shadow(
                    color: Color.brandPrimary.opacity(isFocused ? 0.28 : 0.14),
                    radius: isFocused ? 16 : 10,
                    x: 0,
                    y: isFocused ? 10 : 6
                )
        }
        .accessibilityLabel(accessibilityLabel ?? systemName)
        .buttonStyle(.plain)
    }
}

struct PlayPauseButton: View {
    var isPaused: Bool
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 28, style: .continuous)
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 108, height: 108)
                .background(
                    chrome.fill(Color.brandPrimary.opacity(isFocused ? 0.28 : 0.18))
                )
                .overlay(
                    chrome.stroke(
                        Color.brandPrimary.opacity(isFocused ? 1.0 : 0.5),
                        lineWidth: isFocused ? 2 : 1
                    )
                )
                .shadow(
                    color: Color.brandPrimary.opacity(isFocused ? 0.34 : 0.18),
                    radius: isFocused ? 20 : 12,
                    x: 0,
                    y: isFocused ? 12 : 8
                )
        }
        .accessibilityLabel(
            isPaused
                ? String(localized: "common.actions.play")
                : String(localized: "common.actions.pause"),
        )
        .buttonStyle(.plain)
    }
}

struct SkipMarkerButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 18, style: .continuous)
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(chrome.fill(.thinMaterial))
            .overlay(
                chrome.stroke(
                    Color.brandPrimary.opacity(isFocused ? 1.0 : 0.4),
                    lineWidth: isFocused ? 2 : 1
                )
            )
            .shadow(
                color: Color.brandPrimary.opacity(isFocused ? 0.25 : 0.12),
                radius: isFocused ? 14 : 8,
                x: 0,
                y: isFocused ? 10 : 6
            )
        }
        .accessibilityLabel(title)
        .buttonStyle(.plain)
    }
}

struct PlayerSettingButton: View {
    var systemImage: String
    var action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 14, style: .continuous)
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    chrome.fill(Color.brandPrimary.opacity(isFocused ? 0.24 : 0.14))
                )
                .overlay(
                    chrome.stroke(
                        Color.brandPrimary.opacity(isFocused ? 1.0 : 0.42),
                        lineWidth: isFocused ? 2 : 1
                    )
                )
                .shadow(
                    color: Color.brandPrimary.opacity(isFocused ? 0.24 : 0.1),
                    radius: isFocused ? 14 : 8,
                    x: 0,
                    y: isFocused ? 8 : 5
                )
        }
        .buttonStyle(.plain)
    }
}
