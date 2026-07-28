import SwiftUI

struct PlayerWrapper: View {
    let viewModel: PlayerViewModel
    let showsBufferingOverlay: Bool
    let isPlaybackAuthorized: (PlexItem) -> Bool

    init(
        viewModel: PlayerViewModel,
        showsBufferingOverlay: Bool = true,
        isPlaybackAuthorized: @escaping (PlexItem) -> Bool = { _ in true }
    ) {
        self.viewModel = viewModel
        self.showsBufferingOverlay = showsBufferingOverlay
        self.isPlaybackAuthorized = isPlaybackAuthorized
    }

    var body: some View {
        PlayerView(
            viewModel: viewModel,
            showsBufferingOverlay: showsBufferingOverlay,
            isPlaybackAuthorized: isPlaybackAuthorized
        )
            .transition(.opacity)
    }
}
