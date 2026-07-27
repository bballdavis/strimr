import SwiftUI

private struct PreferredLandscapeArtworkKindKey: EnvironmentKey {
    static let defaultValue: MediaImageViewModel.ArtworkKind? = nil
}

extension EnvironmentValues {
    var preferredLandscapeArtworkKind: MediaImageViewModel.ArtworkKind? {
        get { self[PreferredLandscapeArtworkKindKey.self] }
        set { self[PreferredLandscapeArtworkKindKey.self] = newValue }
    }
}
