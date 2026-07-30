import SwiftUI

extension EnvironmentValues {
    /// Optimistic watched-status overrides keyed by media item ID.
    @Entry var watchedOverrides: [String: Bool] = [:]
}

struct WatchStatusBadge: View {
    let media: MediaDisplayItem

    @Environment(\.watchedOverrides) private var watchedOverrides

    private var isWatched: Bool {
        watchedOverrides[media.id] ?? media.isFullyWatched
    }

    var body: some View {
        if let remaining = media.remainingUnwatchedLeaves {
            unfinishedBadge {
                Text("\(remaining)")
            }
        } else if isWatched {
            watchedIndicator
        }
    }

    private var watchedIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)

            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.3), lineWidth: 1)
        }
        .padding(8)
    }

    private func unfinishedBadge(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65), in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .padding(8)
    }
}
