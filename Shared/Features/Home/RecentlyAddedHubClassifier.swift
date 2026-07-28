import Foundation

/// Identifies the machine-readable hub identifiers Plex uses for recently-added
/// content. Display titles are localized and must not be used for this decision.
enum RecentlyAddedHubClassifier {
    static func isRecentlyAdded(identifier: String) -> Bool {
        let normalized = identifier
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)

        return normalized.contains("recentlyadded")
            || normalized.contains("homerecent")
            || normalized.contains("clipsrecent")
            || normalized.contains("videosrecent")
    }
}
