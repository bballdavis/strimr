import Foundation

struct Library: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let type: PlexItemType
    let sectionId: Int?
    let agent: String

    var isNoneAgentLibrary: Bool {
        !agent.isEmpty && agent.lowercased().contains("none")
    }

    var iconName: String {
        if isNoneAgentLibrary {
            return "play.rectangle.on.rectangle.fill"
        }
        switch type {
        case .movie:
            return "film.fill"
        case .show:
            return "tv.fill"
        case .season, .episode:
            return "play.rectangle.fill"
        case .clip:
            return "play.rectangle.on.rectangle.fill"
        case .collection, .playlist, .unknown:
            return "questionmark.square.fill"
        }
    }

    init(
        id: String,
        title: String,
        type: PlexItemType,
        sectionId: Int? = nil,
        agent: String = "",
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.sectionId = sectionId
        self.agent = agent
    }
}

extension Library {
    init(plexSection: PlexSection) {
        self.init(
            id: plexSection.key,
            title: plexSection.title,
            type: plexSection.type,
            sectionId: Int(plexSection.key),
            agent: plexSection.agent,
        )
    }
}
