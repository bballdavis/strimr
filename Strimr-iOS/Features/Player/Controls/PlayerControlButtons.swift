import SwiftUI

struct PlayerIconButton: View {
    let systemName: String
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 22, style: .continuous)
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(chrome.fill(.thinMaterial))
                .overlay(
                    chrome.stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1),
                )
                .shadow(
                    color: Color.brandPrimary.opacity(0.14),
                    radius: 10,
                    x: 0,
                    y: 6,
                )
        }
        .accessibilityLabel(accessibilityLabel ?? systemName)
        .buttonStyle(.plain)
    }
}

struct PlayPauseButton: View {
    var isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 26, style: .continuous)
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.title.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    chrome.fill(Color.brandPrimary.opacity(0.18)),
                )
                .overlay(
                    chrome.stroke(Color.brandPrimary.opacity(0.52), lineWidth: 1),
                )
                .shadow(
                    color: Color.brandPrimary.opacity(0.18),
                    radius: 12,
                    x: 0,
                    y: 8,
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

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 18, style: .continuous)
            HStack(spacing: 10) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(chrome.fill(.thinMaterial))
            .overlay(
                chrome.stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1),
            )
            .shadow(
                color: Color.brandPrimary.opacity(0.12),
                radius: 8,
                x: 0,
                y: 6,
            )
        }
        .accessibilityLabel(title)
        .buttonStyle(.plain)
    }
}

struct PlayerSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 14, style: .continuous)
            Image(systemName: "gearshape")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(chrome.fill(Color.brandPrimary.opacity(0.14)))
                .overlay(
                    chrome.stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1),
                )
                .shadow(
                    color: Color.brandPrimary.opacity(0.1),
                    radius: 8,
                    x: 0,
                    y: 5,
                )
        }
        .accessibilityLabel(String(localized: "settings.title"))
        .buttonStyle(.plain)
    }
}

struct RotationLockButton: View {
    var isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(cornerRadius: 14, style: .continuous)
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    chrome.fill(Color.brandPrimary.opacity(isLocked ? 0.24 : 0.14)),
                )
                .overlay(
                    chrome.stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1),
                )
                .shadow(
                    color: Color.brandPrimary.opacity(0.1),
                    radius: 8,
                    x: 0,
                    y: 5,
                )
        }
        .accessibilityLabel(String(localized: isLocked ? "player.controls.rotation.unlock" :
                "player.controls.rotation.lock"))
        .buttonStyle(.plain)
    }
}
