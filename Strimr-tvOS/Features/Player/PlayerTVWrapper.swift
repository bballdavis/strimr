import SwiftUI

struct PlayerTVWrapper: View {
    let viewModel: PlayerViewModel
    let onExit: () -> Void
    let isPlaybackAuthorized: (PlexItem) -> Bool

    init(
        viewModel: PlayerViewModel,
        onExit: @escaping () -> Void,
        isPlaybackAuthorized: @escaping (PlexItem) -> Bool = { _ in true }
    ) {
        self.viewModel = viewModel
        self.onExit = onExit
        self.isPlaybackAuthorized = isPlaybackAuthorized
    }

    var body: some View {
        PlayerTVView(
            viewModel: viewModel,
            onExit: onExit,
            isPlaybackAuthorized: isPlaybackAuthorized
        )
    }
}
