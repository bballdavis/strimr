import SwiftUI

struct PlayerTVWrapper: View {
    let viewModel: PlayerViewModel
    let onExit: () -> Void
    let showsBufferingOverlay: Bool
    let isPlaybackAuthorized: (PlexItem) -> Bool

    init(
        viewModel: PlayerViewModel,
        onExit: @escaping () -> Void,
        showsBufferingOverlay: Bool = true,
        isPlaybackAuthorized: @escaping (PlexItem) -> Bool = { _ in true },
    ) {
        self.viewModel = viewModel
        self.onExit = onExit
        self.showsBufferingOverlay = showsBufferingOverlay
        self.isPlaybackAuthorized = isPlaybackAuthorized
    }

    var body: some View {
        PlayerTVView(
            viewModel: viewModel,
            onExit: onExit,
            showsBufferingOverlay: showsBufferingOverlay,
            isPlaybackAuthorized: isPlaybackAuthorized,
        )
    }
}
