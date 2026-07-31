import Foundation

enum PlexProductIdentity {
    static let name = productName(in: Bundle.main.infoDictionary)

    static func productName(in infoDictionary: [String: Any]?) -> String {
        let candidates = [
            infoDictionary?["CFBundleDisplayName"] as? String,
            infoDictionary?["CFBundleName"] as? String
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Strimr"
    }
}
