import SwiftUI

enum SharePlayPresentationPolicy: Sendable {
    case enabled
    case hidden
}

private struct SharePlayPresentationPolicyKey: EnvironmentKey {
    static let defaultValue = SharePlayPresentationPolicy.enabled
}

extension EnvironmentValues {
    var sharePlayPresentationPolicy: SharePlayPresentationPolicy {
        get { self[SharePlayPresentationPolicyKey.self] }
        set { self[SharePlayPresentationPolicyKey.self] = newValue }
    }
}
