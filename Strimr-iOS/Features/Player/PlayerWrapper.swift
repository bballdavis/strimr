import SwiftUI

struct PlayerWrapper: View {
    let viewModel: PlayerViewModel
    let isPlaybackAuthorized: (PlexItem) -> Bool

    init(
        viewModel: PlayerViewModel,
        isPlaybackAuthorized: @escaping (PlexItem) -> Bool = { _ in true }
    ) {
        self.viewModel = viewModel
        self.isPlaybackAuthorized = isPlaybackAuthorized
    }

    var body: some View {
        PlayerView(
            viewModel: viewModel,
            isPlaybackAuthorized: isPlaybackAuthorized
        )
            .transition(.opacity)
    }
}
