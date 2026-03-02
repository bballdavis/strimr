import Foundation

struct Library: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let type: PlexItemType
    let sectionId: Int?
    /// Plex agent identifier, e.g. "tv.plex.agents.movie", "tv.plex.agents.series".
    /// Libraries using the special "none" agent (personal media, YouTube, etc.) do not
    /// have MPAA/TV ratings and should be treated as "other video" content.
    let agent: String

    /// `true` when the Plex library uses the "none" metadata agent.
    /// These libraries (YouTube, Home Videos, personal clips) are not classified
    /// as movie or TV content, even if their section type is declared as `.movie`.
    var isNoneAgentLibrary: Bool {
        // Only flag as none-agent when the agent string explicitly contains "none"
        // (e.g. "tv.plex.agents.none"). An empty agent means unknown/unset —
        // those libraries are real movie/TV sections, not personal-media buckets.
        !agent.isEmpty && agent.lowercased().contains("none")
    }

    var iconName: String {
        // "Other Videos" / personal-media libraries (none agent) get a collection-play icon
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
