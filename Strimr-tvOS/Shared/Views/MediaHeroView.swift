import SwiftUI
import UIKit

struct MediaHeroBackgroundView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem

    @State private var imageURL: URL?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MediaBackdropGradient(colors: MediaBackdropGradient.colors(for: .playable(media)))
                    .ignoresSafeArea()

                HeroImageView(imageURL: imageURL)
                    .frame(
                        width: (proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing) * 0.66,
                        height: (proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) * 0.66,
                    )
                    .clipped()
                    .overlay(Color.black.opacity(0.2))
                    .mask(HeroMaskView())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea()
            }
        }
        .task(id: media.id) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let path = media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath
        guard let path else {
            imageURL = nil
            return
        }

        do {
            let imageRepository = try ImageRepository(context: plexApiContext)
            imageURL = imageRepository.transcodeImageURL(
                path: path,
                width: 3840,
                height: 2160,
                minSize: 1,
                upscale: 1,
            )
        } catch {
            imageURL = nil
        }
    }
}

struct MediaHeroContentView: View {
    let media: MediaItem

    private var summaryLineLimit: Int {
        #if os(tvOS)
        2
        #else
        3
        #endif
    }

    var body: some View {
        heroContent
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(media.primaryLabel)
                .font(heroTitleFont)
                .lineLimit(2)

            if let secondary = media.secondaryLabel, media.type != .movie, media.type != .show {
                Text(secondary)
                    .font(heroSecondaryFont)
                    .foregroundStyle(.brandSecondary)
            }

            metadataLine
            genresLine

            if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(heroSummaryFont)
                    .foregroundStyle(.brandSecondary)
                    .lineLimit(summaryLineLimit)
                    .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
            }
        }
    }

    private var summaryLineHeight: CGFloat {
        #if os(tvOS)
        UIFont.preferredFont(forTextStyle: .footnote).lineHeight
        #else
        UIFont.preferredFont(forTextStyle: .callout).lineHeight
        #endif
    }

    private var heroTitleFont: Font {
        #if os(tvOS)
        .title3.bold()
        #else
        .title2.bold()
        #endif
    }

    private var heroSecondaryFont: Font {
        #if os(tvOS)
        .subheadline
        #else
        .headline
        #endif
    }

    private var heroSummaryFont: Font {
        #if os(tvOS)
        .footnote
        #else
        .callout
        #endif
    }

    @ViewBuilder
    private var metadataLine: some View {
        let items = metadataItems
        if !items.isEmpty {
            HStack(spacing: 16) {
                ForEach(items.indices, id: \.self) { index in
                    Text(items[index])
                }
            }
            .font(metadataFont)
            .foregroundStyle(.brandSecondary)
        }
    }

    @ViewBuilder
    private var genresLine: some View {
        let genres = media.genres
        if !genres.isEmpty {
            HStack(spacing: 12) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                }
            }
            .font(genresFont)
            .foregroundStyle(.brandSecondary)
            .lineLimit(1)
        }
    }

    private var metadataFont: Font {
        #if os(tvOS)
        .footnote
        #else
        .subheadline
        #endif
    }

    private var genresFont: Font {
        #if os(tvOS)
        .caption2
        #else
        .caption
        #endif
    }

    private var metadataItems: [String] {
        var items: [String] = []
        if let tertiary = media.tertiaryLabel {
            items.append(tertiary)
        }
        if let year = yearText {
            items.append(year)
        }
        if let runtime = runtimeText {
            items.append(runtime)
        }
        if let contentRating = media.contentRating {
            items.append(contentRating)
        }
        return items
    }

    private var runtimeText: String? {
        guard let duration = media.duration else { return nil }
        return duration.mediaDurationText()
    }

    private var yearText: String? {
        media.year.map(String.init)
    }
}
