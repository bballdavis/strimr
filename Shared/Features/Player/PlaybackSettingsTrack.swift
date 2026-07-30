import SwiftUI

struct PlaybackSettingsTrack: Identifiable, Hashable {
    let track: PlayerTrack
    let plexStream: PlexPartStream?

    var id: Int {
        track.id
    }

    private var plexCodec: String? {
        plexStream?.codec.uppercased()
    }

    private var metadataLabels: [String] {
        var labels: [String] = []
        if track.isDefault {
            labels.append(String(localized: "player.settings.track.default"))
        }
        if track.isForced {
            labels.append(String(localized: "player.settings.track.forced"))
        }
        if track.isHearingImpaired {
            labels.append(String(localized: "player.settings.track.sdh"))
        }
        if track.isCommentary {
            labels.append(String(localized: "player.settings.track.commentary"))
        }
        if track.isExternal {
            labels.append(String(localized: "player.settings.track.external"))
        }
        return labels
    }

    var title: String {
        guard plexStream != nil else { return track.displayName }

        if let plexDisplayTitle = plexStream?.displayTitle, !plexDisplayTitle.isEmpty {
            switch track.type {
            case .subtitle:
                if let plexCodec {
                    return "\(plexDisplayTitle) (\(plexCodec))"
                }
                return plexDisplayTitle
            default:
                return plexDisplayTitle
            }
        }

        return track.displayName
    }

    var subtitle: String? {
        guard plexStream != nil else {
            return combinedSubtitle(track.codec?.uppercased())
        }

        if let plexTitle = plexStream?.title, !plexTitle.isEmpty {
            return combinedSubtitle(plexTitle)
        }

        return combinedSubtitle(plexCodec ?? track.codec?.uppercased())
    }

    private func combinedSubtitle(_ primary: String?) -> String? {
        let values = [primary].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        } + metadataLabels

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }
}

struct TrackSelectionRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void
    #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
    #endif

    private var backgroundColor: Color {
        #if os(tvOS)
            if isSelected {
                return Color.brandPrimary.opacity(isFocused ? 0.24 : 0.16)
            }
            return Color.white.opacity(isFocused ? 0.12 : 0.07)
        #else
            if isSelected {
                return Color.brandPrimary.opacity(0.16)
            }
            return Color.white.opacity(0.07)
        #endif
    }

    private var borderColor: Color {
        #if os(tvOS)
            if isSelected {
                return Color.brandPrimary.opacity(isFocused ? 1.0 : 0.7)
            }
            return Color.white.opacity(isFocused ? 0.26 : 0.16)
        #else
            if isSelected {
                return Color.brandPrimary.opacity(0.7)
            }
            return Color.white.opacity(0.16)
        #endif
    }

    private var foregroundColor: Color {
        isSelected ? .white : .primary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(foregroundColor)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundColor),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1),
            )
            #if os(tvOS)
            .shadow(
                color: isSelected ? Color.brandPrimary.opacity(0.18) : .clear,
                radius: 6,
                x: 0,
                y: 4,
            )
            #else
            .shadow(
                        color: isSelected ? Color.brandPrimary.opacity(0.18) : .clear,
                        radius: 6,
                        x: 0,
                        y: 4,
                    )
            #endif
                    .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityValue(isSelected ? "selected" : "not selected")
    }
}
