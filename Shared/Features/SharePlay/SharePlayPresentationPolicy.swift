import SwiftUI

enum SharePlayPresentationPolicy: Sendable {
    case enabled
    case hidden
}

extension EnvironmentValues {
    @Entry var sharePlayPresentationPolicy: SharePlayPresentationPolicy = .enabled
}
