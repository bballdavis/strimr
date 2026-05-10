import SwiftUI

struct MediaCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    #if os(tvOS)
        @Environment(MediaFocusModel.self) private var focusModel
        @FocusState private var isFocused: Bool
    #endif

    let size: CGSize
    let media: MediaDisplayItem
    let artworkKind: MediaImageViewModel.ArtworkKind
    let showsLabels: Bool
    let onTap: () -> Void
    let onLongPress: (() -> Void)?

    private var progress: Double? {
        media.viewProgressPercentage.map { $0 / 100 }
    }

    private let artworkCornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            artwork
            #if os(tvOS)
            .scaleEffect(isFocused ? 1.08 : 1)
            .shadow(color: isFocused ? Color.accentColor.opacity(0.72) : .clear, radius: isFocused ? 22 : 0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            #endif

            if showsLabels {
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.primaryLabel)
                        .font(primaryLabelFont)
                        .lineLimit(1)
                    if showsClipMetadataRow {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(media.secondaryLabel ?? "")
                                .font(secondaryLabelFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(clipDurationText ?? "")
                                .font(secondaryLabelFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(media.secondaryLabel ?? "")
                            .font(secondaryLabelFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(media.tertiaryLabel ?? "")
                        .font(secondaryLabelFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: size.width, alignment: .leading)
        #if os(tvOS)
            .focusEffectDisabled()
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused, let playableItem = media.playableItem {
                    focusModel.focusedMedia = playableItem
                }
            }
            .onPlayPauseCommand(perform: onTap)
        #endif
            .onTapGesture(perform: onTap)
            .onLongPressGesture {
                onLongPress?()
            }
    }

    private var artwork: some View {
        MediaImageView(
            viewModel: MediaImageViewModel(
                context: plexApiContext,
                artworkKind: artworkKind,
                media: media,
            ),
        )
        .frame(width: size.width, height: size.height)
        .clipShape(
            RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous),
        )
        .overlay(alignment: .topTrailing) {
            #if !os(tvOS)
            WatchStatusBadge(media: media)
            #endif
        }
        .overlay(alignment: .bottomLeading) {
            if let progress {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: size.width)
                    Rectangle()
                        .fill(.brandPrimary)
                        .frame(width: size.width * progress)
                }
                .frame(width: size.width, height: 8)
                .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.7), lineWidth: 1)
                }
            }
        }
    }

    private var labelSpacing: CGFloat {
        #if os(tvOS)
            20
        #else
            8
        #endif
    }

    private var primaryLabelFont: Font {
        #if os(tvOS)
            size.width < 180 ? .footnote : .subheadline
        #else
            .subheadline
        #endif
    }

    private var secondaryLabelFont: Font {
        #if os(tvOS)
            size.width < 180 ? .caption2 : .footnote
        #else
            .footnote
        #endif
    }

    private var showsClipMetadataRow: Bool {
        size.width > size.height && (media.secondaryLabel != nil || clipDurationText != nil)
    }

    private var clipDurationText: String? {
        media.playableItem?.duration?.mediaDurationText()
    }
}
