import AppKit
import CoreFoundation
import SQLite3
import Security
import SwiftUI
import UniformTypeIdentifiers
import WebKit

#if !DENBOX_TESTING
@main
struct DenboxApp: App {
    @StateObject private var model = LibraryModel()
    @AppStorage(DenboxLanguage.preferenceKey) private var interfaceLanguage = DenboxLanguage.defaultCode

    var body: some Scene {
        WindowGroup("Denbox") {
            MainWindow()
                .environmentObject(model)
                .environmentObject(model.downloadManager)
                .environment(\.font, .denbox(size: 13))
                .environment(\.locale, DenboxLanguage.locale(for: interfaceLanguage))
                .environment(\.layoutDirection, DenboxLanguage.layoutDirection(for: interfaceLanguage))
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)

        WindowGroup("Denbox Player", id: "denbox-player") {
            PlayerWindowHost()
                .environmentObject(model)
                .environmentObject(model.downloadManager)
                .environment(\.font, .denbox(size: 13))
                .environment(\.locale, DenboxLanguage.locale(for: interfaceLanguage))
                .environment(\.layoutDirection, DenboxLanguage.layoutDirection(for: interfaceLanguage))
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}
#endif

enum LibrarySection: String, CaseIterable, Identifiable {
    case home = "Home"
    case forYou = "For You"
    case genres = "Genres"
    case continueWatching = "Continue Watching"
    case watchHistory = "Watch History"
    case viewingStats = "Viewing Stats"
    case movies = "Movies"
    case shows = "TV Shows"
    case imdbCharts = "IMDb Charts"
    case releaseCalendar = "Release Calendar"
    case imdbPeople = "IMDb People"
    case imdbFranchises = "IMDb Franchises"
    case watchlist = "My List"
    case myRatings = "My Ratings"
    case downloads = "Downloads"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .forYou: "sparkles.tv"
        case .genres: "square.grid.2x2"
        case .continueWatching: "play.rectangle"
        case .watchHistory: "clock.arrow.circlepath"
        case .viewingStats: "chart.bar.fill"
        case .movies: "film"
        case .shows: "tv"
        case .imdbCharts: "chart.bar.xaxis"
        case .releaseCalendar: "calendar"
        case .imdbPeople: "person.2"
        case .imdbFranchises: "rectangle.stack"
        case .watchlist: "bookmark"
        case .myRatings: "star"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let apiID: String?
    let title: String
    let subtitle: String
    let synopsis: String
    let year: String
    let kind: String
    let symbol: String
    let palette: Int
    let artworkURL: URL?
    let isRemote: Bool
    let matchingTitles: [String]
    let imdbID: String?
    let genres: [String]
    let imdbRating: String?
    let imdbVotes: Int?

    init(
        id: String,
        apiID: String? = nil,
        title: String,
        subtitle: String,
        synopsis: String,
        year: String,
        kind: String,
        symbol: String,
        palette: Int,
        artworkURL: URL? = nil,
        isRemote: Bool = false,
        matchingTitles: [String] = [],
        imdbID: String? = nil,
        genres: [String] = [],
        imdbRating: String? = nil,
        imdbVotes: Int? = nil
    ) {
        self.id = id
        self.apiID = apiID
        self.title = title
        self.subtitle = subtitle
        self.synopsis = synopsis
        self.year = year
        self.kind = kind
        self.symbol = symbol
        self.palette = palette
        self.artworkURL = artworkURL
        self.isRemote = isRemote
        self.matchingTitles = matchingTitles
        self.imdbID = imdbID
        self.genres = genres
        self.imdbRating = imdbRating
        self.imdbVotes = imdbVotes
    }
}

struct MediaStreamSource: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let headers: [String: String]
}

enum MediaStreamSourceSelection {
    private static let qualityExpression = try! NSRegularExpression(
        pattern: #"\b(2160p|1440p|1080p|720p|576p|540p|480p|360p|240p|4k|uhd|fhd|hd|sd)\b"#,
        options: [.caseInsensitive]
    )

    static func preferred(
        in sources: [MediaStreamSource],
        selectedID: String? = nil,
        selectedTitle: String? = nil
    ) -> MediaStreamSource? {
        guard !sources.isEmpty else { return nil }
        if let selectedID, let exact = sources.first(where: { $0.id == selectedID }) { return exact }
        guard let selectedTitle else { return sources.first }

        let normalizedTitle = normalize(selectedTitle)
        if let exact = sources.first(where: { normalize($0.title) == normalizedTitle }) { return exact }
        if let quality = qualityToken(selectedTitle),
           let sameQuality = sources.first(where: { qualityToken($0.title) == quality }) {
            return sameQuality
        }
        return sources.first
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func qualityToken(_ value: String) -> String? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = qualityExpression.firstMatch(in: value, range: range),
              let tokenRange = Range(match.range(at: 1), in: value) else { return nil }
        return value[tokenRange].lowercased()
    }
}

struct MediaEpisode: Identifiable, Sendable {
    let id: String
    let title: String
    let episodeLabel: String
    let synopsis: String
    let duration: String?
    let artworkURL: URL?
    let sources: [MediaStreamSource]
    let downloadSources: [MediaStreamSource]
    let imdbRating: String?
    let imdbVotes: Int?
    let matchingTitles: [String]
    let imdbID: String?

    init(
        id: String,
        title: String,
        episodeLabel: String,
        synopsis: String,
        duration: String?,
        artworkURL: URL?,
        sources: [MediaStreamSource],
        downloadSources: [MediaStreamSource],
        imdbRating: String?,
        imdbVotes: Int?,
        matchingTitles: [String],
        imdbID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.episodeLabel = episodeLabel
        self.synopsis = synopsis
        self.duration = duration
        self.artworkURL = artworkURL
        self.sources = sources
        self.downloadSources = downloadSources
        self.imdbRating = imdbRating
        self.imdbVotes = imdbVotes
        self.matchingTitles = matchingTitles
        self.imdbID = imdbID
    }
}

struct MediaSeason: Identifiable, Sendable {
    let id: String
    let title: String
    let episodes: [MediaEpisode]
}

struct MediaDetails: Sendable {
    let description: String?
    let year: String?
    let rating: String?
    let runtime: String?
    let genres: [String]
    let country: String?
    let director: String?
    let cast: [String]
    let sources: [MediaStreamSource]
    let downloadSources: [MediaStreamSource]
    let seasons: [MediaSeason]
    let imdbID: String?
    let imdbRating: String?
    let imdbVotes: Int?
    let similarSeries: [IMDbTitleMetadata]
    var castPeople: [IMDbPersonMetadata] = []
    var ratingSource: String? = nil
    var tagline: String? = nil
    var originalTitle: String? = nil
    var status: String? = nil
    var contentRating: String? = nil
    var originalLanguage: String? = nil
    var seasonCount: Int? = nil
    var episodeCount: Int? = nil
    var networks: [String]? = nil
    var productionCompanies: [String]? = nil
    var writers: [String]? = nil
    var keywords: [String]? = nil
    var trailerURL: URL? = nil
    var homepageURL: URL? = nil
    var backdropURL: URL? = nil

    var hasUsefulContent: Bool {
        !sources.isEmpty || !downloadSources.isEmpty || !seasons.isEmpty
            || description?.isEmpty == false || year?.isEmpty == false
            || rating?.isEmpty == false || !genres.isEmpty || !cast.isEmpty
            || hasSupplementalMetadata
    }

    var hasSupplementalMetadata: Bool {
        tagline?.nilIfEmpty != nil || originalTitle?.nilIfEmpty != nil || status?.nilIfEmpty != nil
            || contentRating?.nilIfEmpty != nil || originalLanguage?.nilIfEmpty != nil
            || seasonCount != nil || episodeCount != nil || networks?.isEmpty == false
            || productionCompanies?.isEmpty == false || writers?.isEmpty == false || keywords?.isEmpty == false
            || trailerURL != nil || homepageURL != nil
    }

    var hasPlayableResources: Bool {
        !sources.isEmpty || !downloadSources.isEmpty
            || seasons.flatMap(\.episodes).contains { !$0.sources.isEmpty || !$0.downloadSources.isEmpty }
    }
}

extension MediaItem {
    func applyingIMDb(_ metadata: IMDbTitleMetadata) -> MediaItem {
        MediaItem(
            id: id,
            apiID: apiID,
            title: title,
            subtitle: subtitle,
            synopsis: synopsis,
            year: year,
            kind: kind,
            symbol: symbol,
            palette: palette,
            artworkURL: artworkURL,
            isRemote: isRemote,
            matchingTitles: matchingTitles,
            imdbID: metadata.tconst,
            genres: metadata.genres,
            imdbRating: metadata.rating.map { String(format: "%.1f", $0) },
            imdbVotes: metadata.votes
        )
    }

    func applyingReference(_ metadata: ReferenceTitleMetadata) -> MediaItem {
        MediaItem(
            id: id,
            apiID: apiID,
            title: title,
            subtitle: subtitle,
            synopsis: PersianMetadataText.preferredSynopsis(from: [synopsis, metadata.synopsis]),
            year: year.nilIfEmpty ?? metadata.year ?? year,
            kind: kind,
            symbol: symbol,
            palette: palette,
            artworkURL: artworkURL ?? metadata.posterURL,
            isRemote: isRemote,
            matchingTitles: matchingTitles,
            imdbID: imdbID,
            genres: genres.isEmpty ? metadata.genres : genres,
            imdbRating: imdbRating,
            imdbVotes: imdbVotes
        )
    }

    func applyingPublicTitleMetadata(_ sources: [PublicTitleMetadata]) -> MediaItem {
        guard !sources.isEmpty else { return self }
        let ordered = sources.sorted { lhs, rhs in
            let lhsPriority = lhs.provider == .filimo ? 0 : 1
            let rhsPriority = rhs.provider == .filimo ? 0 : 1
            return lhsPriority < rhsPriority
        }
        let publicSynopsis = ordered.first(where: \.hasPersianSynopsis)?.synopsis
        let fallbackSynopsis = ordered.first {
            !$0.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.synopsis
        let resolvedSynopsis = publicSynopsis ?? synopsis.nilIfEmpty ?? fallbackSynopsis ?? synopsis
        let resolvedArtwork = ordered.compactMap(\.posterURL).first ?? artworkURL
        let resolvedYear = year.nilIfEmpty ?? ordered.compactMap { $0.year?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }.first ?? year
        var seenPublicGenres = Set<String>()
        let publicGenres = Array(ordered.flatMap { $0.genres ?? [] }
            .filter { seenPublicGenres.insert($0).inserted }.prefix(12))
        let resolvedGenres = genres.isEmpty ? publicGenres : genres
        guard resolvedSynopsis != synopsis || resolvedArtwork != artworkURL
                || resolvedYear != year || resolvedGenres != genres else { return self }
        return MediaItem(
            id: id,
            apiID: apiID,
            title: title,
            subtitle: subtitle,
            synopsis: resolvedSynopsis,
            year: resolvedYear,
            kind: kind,
            symbol: symbol,
            palette: palette,
            artworkURL: resolvedArtwork,
            isRemote: isRemote,
            matchingTitles: matchingTitles,
            imdbID: imdbID,
            genres: resolvedGenres,
            imdbRating: imdbRating,
            imdbVotes: imdbVotes
        )
    }
}

private struct ImportedCatalog: Decodable {
    let items: [ImportedItem]?
    let movies: [ImportedItem]?
    let series: [ImportedItem]?
    let posters: [ImportedItem]?
}

private struct ImportedItem: Decodable {
    let id: String?
    let title: String
    let type: String?
    let year: String?
    let description: String?
    let synopsis: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, type, year, description, synopsis
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let stringID = try? values.decode(String.self, forKey: .id)
        let numericID = try? values.decode(Int.self, forKey: .id)
        id = stringID ?? numericID.map(String.init)
        title = try values.decode(String.self, forKey: .title)
        type = try? values.decode(String.self, forKey: .type)
        let stringYear = try? values.decode(String.self, forKey: .year)
        let numericYear = try? values.decode(Int.self, forKey: .year)
        year = stringYear ?? numericYear.map(String.init)
        description = try? values.decode(String.self, forKey: .description)
        synopsis = try? values.decode(String.self, forKey: .synopsis)
    }
}

enum MediaTitleMatching {
    private static let alphanumeric = CharacterSet.alphanumerics
    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: normalizationLocale)
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(folded.unicodeScalars.count)
        for scalar in folded.unicodeScalars where alphanumeric.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        let maximumLength = max(left.count, right.count)
        guard maximumLength > 0 else { return 1 }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for (row, character) in left.enumerated() {
            current[0] = row + 1
            for column in right.indices {
                current[column + 1] = min(
                    current[column] + 1,
                    previous[column + 1] + 1,
                    previous[column] + (character == right[column] ? 0 : 1)
                )
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[right.count]) / Double(maximumLength)
    }

    static func similarity(_ lhs: String, _ rhs: String, atLeast threshold: Double) -> Double? {
        let left = Array(lhs)
        let right = Array(rhs)
        let maximumLength = max(left.count, right.count)
        guard maximumLength > 0 else { return lhs == rhs ? 1 : nil }
        let maximumDistance = Int(floor((1 - threshold) * Double(maximumLength) + 1e-9))
        guard abs(left.count - right.count) <= maximumDistance else { return nil }

        let infinity = maximumDistance + 1
        var previous = Array(repeating: infinity, count: right.count + 1)
        for column in 0...min(right.count, maximumDistance) { previous[column] = column }

        for (rowOffset, character) in left.enumerated() {
            let row = rowOffset + 1
            var current = Array(repeating: infinity, count: right.count + 1)
            if row <= maximumDistance { current[0] = row }
            let firstColumn = max(1, row - maximumDistance)
            let lastColumn = min(right.count, row + maximumDistance)
            guard firstColumn <= lastColumn else { return nil }
            var rowMinimum = infinity
            for column in firstColumn...lastColumn {
                let value = min(
                    current[column - 1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + (character == right[column - 1] ? 0 : 1)
                )
                current[column] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > maximumDistance { return nil }
            swap(&previous, &current)
        }

        let distance = previous[right.count]
        guard distance <= maximumDistance else { return nil }
        return 1 - Double(distance) / Double(maximumLength)
    }
}

enum IMDbEpisodeMatcher {
    private struct Posting {
        let episodeIndex: Int
        let occurrences: Int
    }

    static func remap(_ seasons: [MediaSeason], using imdbEpisodes: [IMDbEpisodeMetadata]) -> [MediaSeason] {
        guard !seasons.isEmpty, !imdbEpisodes.isEmpty else { return seasons }

        let normalizedTitles = imdbEpisodes.map { MediaTitleMatching.normalize($0.title) }
        var exactIndex: [String: [Int]] = [:]
        var bigramIndex: [String: [Posting]]?
        var numberedIndex: [String: Int] = [:]
        for (index, title) in normalizedTitles.enumerated() where !title.isEmpty {
            exactIndex[title, default: []].append(index)
            let episode = imdbEpisodes[index]
            let key = "\(episode.season):\(episode.episode)"
            if numberedIndex[key] == nil { numberedIndex[key] = index }
        }

        var unused = Array(repeating: true, count: imdbEpisodes.count)
        var grouped: [Int: [(Int, MediaEpisode)]] = [:]
        for (seasonIndex, season) in seasons.enumerated() {
            for (episodeIndex, episode) in season.episodes.enumerated() {
                var aliases: [String] = []
                for rawTitle in [episode.title] + episode.matchingTitles {
                    let alias = MediaTitleMatching.normalize(rawTitle)
                    if !alias.isEmpty, !aliases.contains(alias) { aliases.append(alias) }
                }
                let exactCandidates = exactCandidateIndexes(aliases: aliases, index: exactIndex, unused: unused)
                let hint = episodeNumberHint(episode.episodeLabel)
                let titleMatchIndex: Int?
                if let exact = bestExactCandidate(exactCandidates, hint: hint, episodes: imdbEpisodes) {
                    titleMatchIndex = exact
                } else {
                    if bigramIndex == nil { bigramIndex = makeBigramIndex(normalizedTitles) }
                    titleMatchIndex = bestFuzzyCandidate(
                        aliases: aliases,
                        normalizedTitles: normalizedTitles,
                        index: bigramIndex ?? [:],
                        unused: unused
                    )
                }
                let numberedMatchIndex = hint.flatMap {
                    numberedIndex["\($0.season):\($0.episode)"]
                }.flatMap { unused[$0] ? $0 : nil }
                let matchIndex = titleMatchIndex ?? numberedMatchIndex

                let matching = matchIndex.map { imdbEpisodes[$0] }
                let actualSeason = matching?.season ?? hint?.season ?? seasonIndex + 1
                let actualNumber = matching?.episode ?? hint?.episode ?? episodeIndex + 1
                if let matchIndex { unused[matchIndex] = false }
                let updated = MediaEpisode(
                    id: episode.id,
                    title: episode.title,
                    episodeLabel: String(format: "S%02dE%02d", actualSeason, actualNumber),
                    synopsis: episode.synopsis,
                    duration: episode.duration,
                    artworkURL: episode.artworkURL,
                    sources: episode.sources,
                    downloadSources: episode.downloadSources,
                    imdbRating: matching?.rating.map { String(format: "%.1f", $0) },
                    imdbVotes: matching?.votes,
                    matchingTitles: episode.matchingTitles,
                    imdbID: matching?.tconst
                )
                grouped[actualSeason, default: []].append((actualNumber, updated))
            }
        }
        return grouped.keys.sorted().map { number in
            MediaSeason(id: "imdb-season-\(number)", title: "Season \(number)",
                        episodes: grouped[number, default: []].sorted { $0.0 < $1.0 }.map(\.1))
        }
    }

    private static func exactCandidateIndexes(aliases: [String], index: [String: [Int]], unused: [Bool]) -> [Int] {
        var result: [Int] = []
        var seen = Set<Int>()
        for alias in aliases {
            for candidate in index[alias] ?? [] where unused[candidate] && seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    private static func bestExactCandidate(
        _ candidates: [Int], hint: (season: Int, episode: Int)?, episodes: [IMDbEpisodeMetadata]
    ) -> Int? {
        candidates.min { lhs, rhs in
            guard let hint else { return lhs < rhs }
            let left = abs(episodes[lhs].episode - hint.episode) + abs(episodes[lhs].season - hint.season) * 3
            let right = abs(episodes[rhs].episode - hint.episode) + abs(episodes[rhs].season - hint.season) * 3
            return left == right ? lhs < rhs : left < right
        }
    }

    private static func bestFuzzyCandidate(
        aliases: [String], normalizedTitles: [String], index: [String: [Posting]], unused: [Bool]
    ) -> Int? {
        var candidates = Set<Int>()
        for alias in aliases {
            let queryCounts = bigramCounts(alias)
            guard !queryCounts.isEmpty else { continue }
            var overlap: [Int: Int] = [:]
            for (gram, queryOccurrences) in queryCounts {
                for posting in index[gram] ?? [] where unused[posting.episodeIndex] {
                    overlap[posting.episodeIndex, default: 0] += min(queryOccurrences, posting.occurrences)
                }
            }
            let queryLength = alias.count
            for (candidate, commonGrams) in overlap {
                let candidateLength = normalizedTitles[candidate].count
                let maximumLength = max(queryLength, candidateLength)
                let maximumDistance = Int(floor(0.07 * Double(maximumLength) + 1e-9))
                guard abs(queryLength - candidateLength) <= maximumDistance else { continue }
                let minimumCommonGrams = max(1, min(queryLength, candidateLength) - 1 - 2 * maximumDistance)
                if commonGrams >= minimumCommonGrams { candidates.insert(candidate) }
            }
        }

        var ranked: [(Int, Double)] = []
        for candidate in candidates where unused[candidate] {
            let score = aliases.compactMap {
                MediaTitleMatching.similarity($0, normalizedTitles[candidate], atLeast: 0.93)
            }.max() ?? 0
            if score >= 0.93 { ranked.append((candidate, score)) }
        }
        ranked.sort { lhs, rhs in lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1 }
        guard let first = ranked.first else { return nil }
        if ranked.count > 1, first.1 - ranked[1].1 < 0.035 { return nil }
        return first.0
    }

    private static func bigramCounts(_ value: String) -> [String: Int] {
        let characters = Array(value)
        guard characters.count > 1 else { return [:] }
        var counts: [String: Int] = [:]
        for index in 0..<(characters.count - 1) {
            counts[String([characters[index], characters[index + 1]]), default: 0] += 1
        }
        return counts
    }

    private static func makeBigramIndex(_ normalizedTitles: [String]) -> [String: [Posting]] {
        var index: [String: [Posting]] = [:]
        for (episodeIndex, title) in normalizedTitles.enumerated() where !title.isEmpty {
            for (gram, count) in bigramCounts(title) {
                index[gram, default: []].append(Posting(episodeIndex: episodeIndex, occurrences: count))
            }
        }
        return index
    }

    private static func episodeNumberHint(_ label: String) -> (season: Int, episode: Int)? {
        let values = label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard values.count == 2 else { return nil }
        return (values[0], values[1])
    }
}

enum IMDbMediaEnricher {
    static func match(_ details: MediaDetails, for item: MediaItem) -> IMDbTitleMetadata? {
        let store = IMDbMetadataStore.shared
        if let imdbID = details.imdbID ?? item.imdbID, let matched = store.title(tconst: imdbID) { return matched }
        return store.matchTitle(title: item.title, year: details.year ?? item.year, kind: item.kind)
    }

    static func enrich(_ details: MediaDetails, for item: MediaItem, matched: IMDbTitleMetadata) -> MediaDetails {
        let store = IMDbMetadataStore.shared
        let castPeople = store.principalPeople(for: matched.tconst)
        let cast = castPeople.map(\.name)
        let seriesEnrichment = item.kind == "Series"
            ? store.enrichment(title: matched.title, year: matched.year.map(String.init) ?? details.year ?? item.year, includeSimilar: false)
            : nil
        let seasons = seriesEnrichment.map { IMDbEpisodeMatcher.remap(details.seasons, using: $0.episodes) } ?? details.seasons
        return MediaDetails(
            description: details.description,
            year: matched.year.map(String.init) ?? details.year,
            rating: details.rating,
            runtime: details.runtime,
            genres: matched.genres.isEmpty ? details.genres : matched.genres,
            country: details.country,
            director: details.director,
            cast: cast.isEmpty ? details.cast : cast,
            sources: details.sources,
            downloadSources: details.downloadSources,
            seasons: seasons,
            imdbID: matched.tconst,
            imdbRating: matched.rating.map { String(format: "%.1f", $0) } ?? details.imdbRating,
            imdbVotes: matched.votes ?? details.imdbVotes,
            similarSeries: [],
            castPeople: castPeople.isEmpty ? details.castPeople : castPeople,
            ratingSource: details.ratingSource,
            tagline: details.tagline,
            originalTitle: details.originalTitle,
            status: details.status,
            contentRating: details.contentRating,
            originalLanguage: details.originalLanguage,
            seasonCount: details.seasonCount,
            episodeCount: details.episodeCount,
            networks: details.networks,
            productionCompanies: details.productionCompanies,
            writers: details.writers,
            keywords: details.keywords,
            trailerURL: details.trailerURL,
            homepageURL: details.homepageURL,
            backdropURL: details.backdropURL
        )
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var section: LibrarySection = .home
    @Published var searchText = ""
    @Published var savedIDs: Set<String> = []
    @Published private(set) var personalRatings: [String: PersonalRating] = [:]
    @Published var selectedItem: MediaItem?
    @Published var playerURL: URL?
    @Published var isPlayerWindowOpen = false
    @Published var playerTitle = "Now Playing"
    @Published var playerHeaders: [String: String] = [:]
    @Published private(set) var playerRequestID = UUID()
    @Published private(set) var isResumingPlayback = false
    @Published var showingSettings = false
    @Published var catalogName = "Local library"
    @Published var selectedGenreFilters: Set<String> = []
    @Published private(set) var connectionStatus = "Loading local database…"
    @Published private(set) var isConnecting = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreMovies = false
    @Published private(set) var hasMoreSeries = false
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var remoteSearchResults: [MediaItem] = []
    @Published private(set) var didFinishRemoteSearch = false
    @Published private(set) var isSearchingRemoteSearch = false
    @Published private(set) var imdbDatasetStatus = "IMDb dataset is not downloaded."
    @Published private(set) var isUpdatingIMDbDataset = false
    @Published private(set) var imdbChartLists: IMDbChartLists?
    @Published private(set) var isLoadingIMDbCharts = false
    @Published private(set) var imdbPeopleAvailable = false
    @Published private(set) var pendingIMDbPersonRequest: IMDbPersonLookupRequest?
    @Published private(set) var publicReferenceStatus = "Open a title to load its IMDb and public reference metadata; results are saved locally."
    @Published private(set) var genreFacets: [IMDbGenreFacet] = []
    @Published private(set) var isLoadingGenreFacets = false
    @Published private(set) var preferredGenres: Set<String> = []
    @Published private(set) var recommendations: [IMDbTitleMetadata] = []
    @Published private(set) var referenceMetadataByID: [String: ReferenceTitleMetadata] = [:]
    @Published private(set) var isLoadingRecommendations = false
    @Published private(set) var continueWatchingItems: [WatchProgress] = []
    @Published private(set) var pendingEpisodeProgress: WatchProgress?
    @Published private(set) var watchHistory: [WatchHistoryEntry] = []
    @Published private(set) var viewingStats = ViewingStats()
    @Published private(set) var isLoadingViewingStats = false
    @Published private(set) var viewingUpdateMessage: String?
    @Published private(set) var resolvingSimilarTitleID: String?
    @Published private(set) var similarTitleSearchMessage: String?
    @Published private(set) var detailsRefreshRevision = 0

    let downloadManager: DownloadManager
    private let database: MediaDatabase
    private let refreshStaleDetailsInBackground: Bool
    private(set) var recentlyRefreshedDetails: [String: MediaDetails] = [:]
    private var searchTask: Task<Void, Never>?
    private var activeRemoteSearchID: UUID?
    private var artworkLookupsInFlight: Set<String> = []
    private var imdbEnrichmentsInFlight: Set<String> = []
    private var imdbRecommendationsInFlight: Set<String> = []
    private var referenceMetadataLookupsInFlight: Set<String> = []
    private var publicMetadataLookupsInFlight: Set<String> = []
    private var referenceCatalogEnrichmentTask: Task<Void, Never>?
    private var referenceCatalogEnrichmentRequested = false
    private var forceTMDBReferenceRefreshRequested = false
    private var recommendationsNeedRefresh = false
    private var catalogRefreshInProgress = false
    private var detailRefreshesInFlight: Set<String> = []
    private var activeRemotePlayback: (
        item: MediaItem,
        episodeID: String?,
        episodeLabel: String?,
        episodeTitle: String?,
        sourceTitle: String?,
        details: MediaDetails?
    )?
    private var activeWatchSessionID: String?
    private var activeWatchProgress: WatchProgress?
    private var viewingStatsTask: Task<Void, Never>?
    private var viewingStatsNeedsRefresh = true
    private var activeWatchPlayerKind = "AVPlayer"
    private var iinaPlaybackMonitor: IINAPlaybackMonitor?
    private var nextMoviePage = 0
    private var nextSeriesPage = 0

    init(
        loadRemoteCatalog: Bool = true,
        refreshStaleDetailsInBackground: Bool = true,
        databaseURL: URL? = nil,
        startBackgroundCatalogEnrichment: Bool = true
    ) {
        self.refreshStaleDetailsInBackground = refreshStaleDetailsInBackground
        let database = MediaDatabase(databaseURL: databaseURL)
        self.database = database
        self.downloadManager = DownloadManager(database: database)
        database.closeUnfinishedWatchSessions()
        selectedGenreFilters = database.loadGenrePreferences(category: "filter")
        preferredGenres = database.loadGenrePreferences(category: "preferred")
        let cached = database.loadCatalog()
        if !cached.isEmpty {
            items = cached
            catalogName = "Denbox Library"
            let movies = cached.filter { $0.kind == "Movie" }.count
            let series = cached.filter { $0.kind == "Series" }.count
            connectionStatus = "Local database · \(movies) movies · \(series) series"
        }
        savedIDs = database.loadSavedIDs()
        personalRatings = database.loadPersonalRatings()
        refreshViewingData()
        if startBackgroundCatalogEnrichment {
            Task { @MainActor [weak self] in
                let summary = await Task.detached(priority: .utility) {
                    IMDbMetadataStore.shared.startupSummary()
                }.value
                guard let self else { return }
                self.imdbPeopleAvailable = summary.hasPeopleData
                if let updated = summary.lastUpdated {
                    self.imdbDatasetStatus = "IMDb dataset ready · updated \(updated.formatted(date: .abbreviated, time: .shortened))"
                }
            }
        }
        if loadRemoteCatalog {
            if SecretVault.read(account: "media-api-key") != nil,
               SecretVault.read(account: "catalog-feed-key") != nil {
                Task { await refreshCatalog() }
            } else if cached.isEmpty {
                connectionStatus = "Add API keys in Settings to load your catalog."
            }
        }
    }

    var visibleItems: [MediaItem] {
        let base: [MediaItem]
        switch section {
        case .home:
            base = items
        case .movies:
            base = items.filter { $0.kind == "Movie" }
        case .shows:
            base = items.filter { $0.kind == "Series" }
        case .imdbCharts, .releaseCalendar, .imdbPeople, .imdbFranchises, .forYou, .genres, .continueWatching, .watchHistory, .viewingStats:
            base = []
        case .watchlist:
            base = items.filter { savedIDs.contains($0.id) }
        case .myRatings:
            base = personalRatings.values.sorted { $0.updatedAt > $1.updatedAt }.map(\.item)
        case .downloads:
            base = []
        }
        let genreFiltered = selectedGenreFilters.isEmpty || section == .myRatings
            ? base
            : base.filter { !Set($0.genres).isDisjoint(with: selectedGenreFilters) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return genreFiltered }
        let localMatches = genreFiltered.filter { item in
            ([item.title, item.subtitle] + item.matchingTitles)
                .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        guard didFinishRemoteSearch, section != .myRatings else { return localMatches }
        var seen = Set(localMatches.map(\.id))
        return localMatches + remoteSearchResults.filter { seen.insert($0.id).inserted }
    }

    func toggleSaved(_ item: MediaItem) {
        if savedIDs.contains(item.id) {
            savedIDs.remove(item.id)
            database.setSaved(item.id, saved: false)
        } else {
            savedIDs.insert(item.id)
            database.setSaved(item.id, saved: true)
        }
    }

    func setPersonalRating(_ rating: Int?, for item: MediaItem) {
        guard rating.map({ (1...5).contains($0) }) ?? true,
              database.setPersonalRating(rating, for: item) else { return }
        if let rating {
            personalRatings[item.id] = PersonalRating(rating: rating, item: item, updatedAt: Date())
        } else {
            personalRatings.removeValue(forKey: item.id)
        }
        invalidateRecommendations()
    }

    func refreshViewingData() {
        continueWatchingItems = database.loadWatchProgress(limit: 500)
            .filter { !$0.isWatched && $0.positionSeconds >= 15 }
        watchHistory = database.loadWatchHistory(limit: 500)
    }

    func refreshViewingStats(force: Bool = false) {
        if force { viewingStatsNeedsRefresh = true }
        guard viewingStatsNeedsRefresh, viewingStatsTask == nil else { return }
        viewingStatsNeedsRefresh = false
        isLoadingViewingStats = true
        viewingStatsTask = Task { [weak self] in
            guard let self else { return }
            let stats = await self.database.viewingStatsAsync()
            self.viewingStats = stats
            self.isLoadingViewingStats = false
            self.viewingStatsTask = nil
            if self.viewingStatsNeedsRefresh { self.refreshViewingStats() }
        }
    }

    private func invalidateViewingStats() {
        viewingStatsNeedsRefresh = true
        if section == .viewingStats { refreshViewingStats() }
    }

    private func updateContinueWatching(with progress: WatchProgress) {
        let existingIndex = continueWatchingItems.firstIndex { $0.id == progress.id }
        guard !progress.isWatched, progress.positionSeconds >= 15 else {
            if let existingIndex { continueWatchingItems.remove(at: existingIndex) }
            return
        }
        if let existingIndex {
            continueWatchingItems[existingIndex] = progress
        } else {
            continueWatchingItems.insert(progress, at: 0)
            if continueWatchingItems.count > 500 {
                continueWatchingItems.removeLast(continueWatchingItems.count - 500)
            }
        }
    }

    func openProgressTitle(_ progress: WatchProgress) {
        guard !progress.mediaID.hasPrefix("local:") else { return }
        let item = items.first(where: { $0.id == progress.mediaID })
            ?? database.loadCatalog().first(where: { $0.id == progress.mediaID })
        guard let item else {
            viewingUpdateMessage = "This title was not found in the saved catalog."
            return
        }
        pendingEpisodeProgress = progress.kind == "Series" ? progress : nil
        viewingUpdateMessage = nil
        selectedItem = item
    }

    func consumePendingEpisodeProgress(for itemID: String) -> WatchProgress? {
        guard let progress = pendingEpisodeProgress, progress.mediaID == itemID else { return nil }
        pendingEpisodeProgress = nil
        return progress
    }

    var hasIMDbData: Bool { IMDbMetadataStore.shared.isAvailable }
    var isTrackingPlayback: Bool { activeWatchSessionID != nil }
    var isCheckingPublicReferences: Bool { referenceCatalogEnrichmentTask != nil }

    func checkPublicReferencesForCatalog(forceTMDB: Bool = false) {
        if forceTMDB { forceTMDBReferenceRefreshRequested = true }
        scheduleCatalogReferenceEnrichment()
    }

    func tmdbCredentialsDidChange(hasToken: Bool) {
        forceTMDBReferenceRefreshRequested = hasToken
    }

    func publicTitleMetadata(mediaID: String, provider: PublicMetadataProvider) -> PublicTitleMetadata? {
        database.loadPublicTitleMetadata(mediaID: mediaID, provider: provider)
    }

    func localizedPersianTitle(mediaID: String) -> String? {
        if let saved = database.loadLocalizedPersianTitle(mediaID: mediaID) { return saved }
        let sources = [PublicMetadataProvider.filimo, .hexDL].compactMap {
            database.loadPublicTitleMetadata(mediaID: mediaID, provider: $0)
        }
        guard let source = sources.first(where: \.hasPersianTitle) else { return nil }
        let englishTitle = items.first(where: { $0.id == mediaID })?.title ?? source.originalTitle ?? ""
        database.saveLocalizedPersianTitle(source.title, englishTitle: englishTitle,
                                            provider: source.provider, mediaID: mediaID)
        return source.title
    }

    func cachedPublicArtwork(mediaID: String) async -> NSImage? {
        await publicArtwork(mediaID: mediaID, shouldDownload: false)
    }

    func loadPublicArtwork(mediaID: String) async -> NSImage? {
        await publicArtwork(mediaID: mediaID, shouldDownload: true)
    }

    private func publicArtwork(mediaID: String, shouldDownload: Bool) async -> NSImage? {
        for provider in [PublicMetadataProvider.filimo, .hexDL] {
            guard let metadata = database.loadPublicTitleMetadata(mediaID: mediaID, provider: provider),
                  let sourceURL = metadata.posterURL else { continue }
            let fileURL: URL?
            if shouldDownload {
                fileURL = await PublicArtworkFileCache.shared.cache(
                    mediaID: mediaID, provider: provider, sourceURL: sourceURL
                )
            } else {
                fileURL = await PublicArtworkFileCache.shared.cachedURL(
                    mediaID: mediaID, provider: provider, sourceURL: sourceURL
                )
            }
            guard let fileURL else { continue }
            let imageData = await Task.detached(priority: .utility) { try? Data(contentsOf: fileURL) }.value
            if let imageData, let image = NSImage(data: imageData) { return image }
        }
        return nil
    }

    func referenceMetadata(mediaID: String) -> ReferenceTitleMetadata? {
        if let cached = referenceMetadataByID[mediaID] { return cached }
        let cached = database.loadReferenceMetadata(mediaID: mediaID)
        if let cached { referenceMetadataByID[mediaID] = cached }
        return cached
    }

    func savePublicTitleMetadata(_ metadata: PublicTitleMetadata, mediaID: String) -> Bool {
        let existing = database.loadPublicTitleMetadata(mediaID: mediaID, provider: metadata.provider)
        let merged = existing.map { metadata.merging($0) } ?? metadata
        guard database.savePublicTitleMetadata(merged, for: mediaID) else { return false }
        database.recordPublicTitleMetadataAttempt(mediaID: mediaID, provider: metadata.provider)
        persistPreferredPersianTitle(mediaID: mediaID)
        applyCachedPublicMetadataToCatalog(mediaID: mediaID)
        return true
    }

    private func persistPreferredPersianTitle(mediaID: String) {
        let sources = [PublicMetadataProvider.filimo, .hexDL].compactMap {
            database.loadPublicTitleMetadata(mediaID: mediaID, provider: $0)
        }
        guard let source = sources.first(where: \.hasPersianTitle) else { return }
        let englishTitle = items.first(where: { $0.id == mediaID })?.title ?? source.originalTitle ?? ""
        database.saveLocalizedPersianTitle(source.title, englishTitle: englishTitle,
                                           provider: source.provider, mediaID: mediaID)
    }

    func refreshPublicTitleMetadata(
        for item: MediaItem,
        force: Bool = false,
        includePageDetails: Bool = false
    ) async -> (attempted: Int, updated: Int) {
        guard item.isRemote, ["Movie", "Series"].contains(item.kind) else { return (0, 0) }
        let providers = PublicMetadataProvider.allCases
        let dueProviders = providers.filter { provider in
            let cached = database.loadPublicTitleMetadata(mediaID: item.id, provider: provider)
            let attemptedAt = database.publicTitleMetadataLastAttempt(mediaID: item.id, provider: provider)
            let lookupDue = PublicTitleMetadataRefreshPolicy.shouldRefresh(
                cached: cached,
                lastAttempt: attemptedAt,
                force: force
            )
            let pageDetailsDue = includePageDetails && (cached?.needsPageDetailsRefresh() ?? false)
            guard lookupDue || pageDetailsDue else { return false }
            return !publicMetadataLookupsInFlight.contains("\(item.id)|\(provider.rawValue)")
        }
        guard !dueProviders.isEmpty else { return (0, 0) }

        let cachedMetadataByProvider = Dictionary(uniqueKeysWithValues: dueProviders.compactMap { provider in
            database.loadPublicTitleMetadata(mediaID: item.id, provider: provider).map { (provider, $0) }
        })

        for provider in dueProviders {
            publicMetadataLookupsInFlight.insert("\(item.id)|\(provider.rawValue)")
        }
        defer {
            for provider in dueProviders {
                publicMetadataLookupsInFlight.remove("\(item.id)|\(provider.rawValue)")
            }
        }

        var updatedCount = 0
        await withTaskGroup(of: (PublicMetadataProvider, PublicTitleMetadata?).self) { group in
            for provider in dueProviders {
                group.addTask {
                    if includePageDetails,
                       let cached = cachedMetadataByProvider[provider],
                       cached.needsPageDetailsRefresh(),
                       !force,
                       !cached.needsAutomaticRefresh() {
                        return (provider, await PublicMetadataDiscoveryService.enrichPageDetails(from: cached))
                    }
                    let discovered = await PublicMetadataDiscoveryService.discover(
                        for: item,
                        provider: provider,
                        includePageDetails: includePageDetails
                    )
                    if let discovered { return (provider, discovered) }
                    if includePageDetails,
                       let cached = cachedMetadataByProvider[provider],
                       cached.needsPageDetailsRefresh() {
                        return (provider, await PublicMetadataDiscoveryService.enrichPageDetails(from: cached))
                    }
                    return (provider, nil)
                }
            }
            for await (provider, discovered) in group {
                guard !Task.isCancelled else { continue }
                if let discovered {
                    let existing = database.loadPublicTitleMetadata(mediaID: item.id, provider: provider)
                    let merged = existing.map { discovered.merging($0) } ?? discovered
                    if database.savePublicTitleMetadata(merged, for: item.id) { updatedCount += 1 }
                }
                database.recordPublicTitleMetadataAttempt(mediaID: item.id, provider: provider)
            }
        }
        if updatedCount > 0 {
            persistPreferredPersianTitle(mediaID: item.id)
            applyCachedPublicMetadataToCatalog(mediaID: item.id)
        }
        return (dueProviders.count, updatedCount)
    }

    private func applyCachedPublicMetadataToCatalog(mediaID: String) {
        guard let index = items.firstIndex(where: { $0.id == mediaID }) else { return }
        let item = items[index]
        let metadata = PublicMetadataProvider.allCases.compactMap {
            database.loadPublicTitleMetadata(mediaID: mediaID, provider: $0)
        }
        let enriched = item.applyingPublicTitleMetadata(metadata)
        if enriched != item {
            items[index] = enriched
            if let rating = personalRatings[mediaID], database.updatePersonalRatingSnapshot(enriched) {
                personalRatings[mediaID] = PersonalRating(rating: rating.rating, item: enriched, updatedAt: rating.updatedAt)
            }
        }
        detailsRefreshRevision += 1
    }

    func exportViewingActivity(to url: URL) {
        let export = ViewingDataExport(
            schemaVersion: 2,
            exportedAt: Date(),
            progress: database.loadWatchProgress(limit: nil, includeWatched: true),
            history: database.loadWatchHistory(limit: nil),
            personalRatings: personalRatings.values.sorted { $0.updatedAt > $1.updatedAt }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(export)
            try data.write(to: url, options: .atomic)
            viewingUpdateMessage = "Viewing data export saved."
        } catch {
            viewingUpdateMessage = "Could not save the viewing data export: \(error.localizedDescription)"
        }
    }

    func prepareViewingDataImport(from url: URL) -> ViewingDataImportPreview? {
        guard !isTrackingPlayback else {
            viewingUpdateMessage = "Close active playback before importing viewing data."
            return nil
        }
        do {
            let maximumImportBytes = 50_000_000
            let startedAccess = url.startAccessingSecurityScopedResource()
            defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.int64Value > Int64(maximumImportBytes) {
                viewingUpdateMessage = "The selected viewing-data file is larger than 50 MB."
                return nil
            }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var data = Data()
            while data.count <= maximumImportBytes {
                let remaining = maximumImportBytes + 1 - data.count
                let chunk = try file.read(upToCount: min(64 * 1024, remaining)) ?? Data()
                guard !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard data.count <= maximumImportBytes else {
                viewingUpdateMessage = "The selected viewing-data file is larger than 50 MB."
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let export = try decoder.decode(ViewingDataExport.self, from: data).validated()
            viewingUpdateMessage = nil
            return ViewingDataImportPreview(fileName: url.lastPathComponent, export: export)
        } catch let error as ViewingDataImportError {
            viewingUpdateMessage = error.localizedDescription
        } catch {
            viewingUpdateMessage = "Could not read viewing data: \(error.localizedDescription)"
        }
        return nil
    }

    @discardableResult
    func mergeViewingData(_ export: ViewingDataExport) -> Bool {
        guard !isTrackingPlayback else {
            viewingUpdateMessage = "Close active playback before importing viewing data."
            return false
        }
        guard let export = try? export.validated(), database.mergeViewingData(export) else {
            viewingUpdateMessage = "Could not merge viewing data. Your existing data was kept."
            return false
        }
        personalRatings = database.loadPersonalRatings()
        refreshViewingData()
        invalidateViewingStats()
        viewingUpdateMessage = "Viewing data merged. Newer local progress and ratings were kept; duplicate sessions were skipped."
        invalidateRecommendations()
        return true
    }

    func clearViewingActivity() {
        guard !isTrackingPlayback else {
            viewingUpdateMessage = "Close active playback before clearing history."
            return
        }
        guard database.clearViewingActivity() else {
            viewingUpdateMessage = "Could not clear viewing history."
            return
        }
        refreshViewingData()
        invalidateViewingStats()
        viewingUpdateMessage = "Viewing history and progress cleared."
        invalidateRecommendations()
    }

    func refreshDiscoveryData() async {
        guard !isLoadingRecommendations else { return }
        isLoadingRecommendations = true
        recommendationsNeedRefresh = false
        defer {
            isLoadingRecommendations = false
            if recommendationsNeedRefresh, section == .forYou {
                Task { await refreshDiscoveryData() }
            }
        }
        let store = IMDbMetadataStore.shared
        let (facets, candidates) = await Task.detached(priority: .userInitiated) {
            (store.genreFacets(), store.discoveryCandidates())
        }.value
        genreFacets = facets
        refreshViewingData()
        let history = watchHistory
        let preferences = preferredGenres
        let userRatings = Array(personalRatings.values)
        let watched = database.loadWatchedIMDbIDs()
        recommendations = await Task.detached(priority: .userInitiated) {
            PersonalizedRecommendationRanker.rank(
                candidates,
                history: history,
                preferredGenres: preferences,
                excluding: watched,
                personalRatings: userRatings,
                limit: 80
            )
        }.value
    }

    func loadGenreFacets() async {
        guard genreFacets.isEmpty, !isLoadingGenreFacets, IMDbMetadataStore.shared.isAvailable else { return }
        isLoadingGenreFacets = true
        defer { isLoadingGenreFacets = false }
        let facets = await Task.detached(priority: .utility) {
            IMDbMetadataStore.shared.genreFacets()
        }.value
        genreFacets = facets
    }

    private func invalidateRecommendations() {
        recommendations = []
        recommendationsNeedRefresh = true
        if section == .forYou, !isLoadingRecommendations {
            Task { await refreshDiscoveryData() }
        }
    }

    nonisolated private static func decodeCatalogMetadata(
        _ payloads: CatalogMetadataPayloads
    ) -> [String: CachedCatalogMetadata] {
        let decoder = JSONDecoder()
        var result: [String: CachedCatalogMetadata] = [:]
        for (mediaID, data) in payloads.references {
            result[mediaID] = CachedCatalogMetadata(
                reference: try? decoder.decode(ReferenceTitleMetadata.self, from: data),
                publicTitles: [],
                publicAttempts: payloads.publicAttempts[mediaID] ?? [:]
            )
        }
        for (mediaID, values) in payloads.publicTitles {
            let publicTitles = values.compactMap { try? decoder.decode(PublicTitleMetadata.self, from: $0) }
            let cached = result[mediaID] ?? CachedCatalogMetadata(
                reference: nil,
                publicTitles: [],
                publicAttempts: payloads.publicAttempts[mediaID] ?? [:]
            )
            result[mediaID] = CachedCatalogMetadata(
                reference: cached.reference,
                publicTitles: publicTitles,
                publicAttempts: cached.publicAttempts
            )
        }
        for (mediaID, attempts) in payloads.publicAttempts where result[mediaID] == nil {
            result[mediaID] = CachedCatalogMetadata(reference: nil, publicTitles: [], publicAttempts: attempts)
        }
        return result
    }

    private func scheduleCatalogReferenceEnrichment() {
        referenceCatalogEnrichmentRequested = true
        guard referenceCatalogEnrichmentTask == nil else { return }
        referenceCatalogEnrichmentRequested = false
        referenceCatalogEnrichmentTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            let forceTMDB = self.forceTMDBReferenceRefreshRequested
            self.forceTMDBReferenceRefreshRequested = false
            let tmdbToken = SecretVault.read(account: "tmdb-read-access-token")
            let hasTMDBToken = !(tmdbToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            var completedCount = 0
            defer {
                self.referenceCatalogEnrichmentTask = nil
                if completedCount > 0 {
                    self.publicReferenceStatus = "Checked public references for \(completedCount) titles."
                } else if self.items.isEmpty {
                    self.publicReferenceStatus = "Load a catalog to check public metadata references."
                } else {
                    self.publicReferenceStatus = "Public reference metadata is up to date."
                }
                if self.referenceCatalogEnrichmentRequested {
                    self.referenceCatalogEnrichmentRequested = false
                    self.scheduleCatalogReferenceEnrichment()
                }
            }

            while !Task.isCancelled {
                let cachePayloads = self.database.loadCatalogMetadataPayloads(for: Set(self.items.map(\.id)))
                let cachedMetadata = await Task.detached(priority: .utility) {
                    Self.decodeCatalogMetadata(cachePayloads)
                }.value
                let pending = self.items.compactMap { item -> (MediaItem, ReferenceTitleMetadata?, String)? in
                    guard item.kind == "Movie" || item.kind == "Series" else { return nil }
                    let imdbID = item.imdbID
                    let cached = cachedMetadata[item.id]?.reference
                    guard ReferenceMetadataService.shouldRefresh(cached, for: item, imdbID: imdbID,
                                                                  hasTMDBToken: hasTMDBToken,
                                                                  forceTMDB: forceTMDB) else { return nil }
                    let lookupKey = "\(item.id)|\(imdbID ?? "series")"
                    guard self.referenceMetadataLookupsInFlight.insert(lookupKey).inserted else { return nil }
                    return (item, cached, lookupKey)
                }
                guard !pending.isEmpty else { break }

                let batch = Array(pending.prefix(24))
                for skipped in pending.dropFirst(batch.count) {
                    self.referenceMetadataLookupsInFlight.remove(skipped.2)
                }
                self.publicReferenceStatus = "Checking public metadata for \(batch.count) titles…"
                await withTaskGroup(of: (String, String, ReferenceTitleMetadata).self) { group in
                    var nextIndex = 0
                    for input in batch.prefix(3) {
                        group.addTask {
                            let metadata = await ReferenceMetadataService.fetch(
                                for: input.0,
                                imdbID: input.0.imdbID,
                                existing: input.1,
                                tmdbToken: tmdbToken,
                                forceTMDB: forceTMDB
                            )
                            return (input.0.id, input.2, metadata)
                        }
                        nextIndex += 1
                    }

                    while let (mediaID, lookupKey, metadata) = await group.next() {
                        self.referenceMetadataLookupsInFlight.remove(lookupKey)
                        let latest = self.database.loadReferenceMetadata(mediaID: mediaID)
                        let combined = metadata.merging(latest ?? .empty())
                        self.database.saveReferenceMetadata(combined, mediaID: mediaID)
                        self.referenceMetadataByID[mediaID] = combined
                        if let index = self.items.firstIndex(where: { $0.id == mediaID }) {
                            self.items[index] = self.items[index].applyingReference(combined)
                        }
                        completedCount += 1

                        if nextIndex < batch.count {
                            let input = batch[nextIndex]
                            group.addTask {
                                let metadata = await ReferenceMetadataService.fetch(
                                    for: input.0,
                                    imdbID: input.0.imdbID,
                                    existing: input.1,
                                    tmdbToken: tmdbToken,
                                    forceTMDB: forceTMDB
                                )
                                return (input.0.id, input.2, metadata)
                            }
                            nextIndex += 1
                        }
                    }
                }
            }
        }
    }

    func toggleGenreFilter(_ genre: String) {
        if selectedGenreFilters.contains(genre) { selectedGenreFilters.remove(genre) }
        else { selectedGenreFilters.insert(genre) }
        database.saveGenrePreferences(selectedGenreFilters, category: "filter")
    }

    func clearGenreFilters() {
        selectedGenreFilters.removeAll()
        database.saveGenrePreferences([], category: "filter")
    }

    func browseGenre(_ genre: String, kind: String? = nil) {
        let value = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        selectedGenreFilters = [value]
        database.saveGenrePreferences(selectedGenreFilters, category: "filter")
        searchText = ""
        switch kind {
        case "Movie": section = .movies
        case "Series": section = .shows
        default: section = .home
        }
    }

    func openIMDbPerson(_ person: IMDbPersonMetadata, imageURL: URL? = nil) {
        pendingIMDbPersonRequest = IMDbPersonLookupRequest(
            nconst: person.nconst, name: person.name, imageURL: imageURL ?? person.imageURL
        )
        searchText = ""
        section = .imdbPeople
    }

    func openIMDbPerson(named name: String, imdbID: String? = nil, imageURL: URL? = nil) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let matchedIMDbID = imdbID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nconst = matchedIMDbID.flatMap {
            $0.range(of: #"^nm\d{7,10}$"#, options: .regularExpression) == nil ? nil : $0
        }
        pendingIMDbPersonRequest = IMDbPersonLookupRequest(nconst: nconst, name: value, imageURL: imageURL)
        searchText = ""
        section = .imdbPeople
    }

    func consumePendingIMDbPersonRequest() -> IMDbPersonLookupRequest? {
        defer { pendingIMDbPersonRequest = nil }
        return pendingIMDbPersonRequest
    }

    func togglePreferredGenre(_ genre: String) {
        if preferredGenres.contains(genre) { preferredGenres.remove(genre) }
        else { preferredGenres.insert(genre) }
        database.saveGenrePreferences(preferredGenres, category: "preferred")
        invalidateRecommendations()
    }

    func saveAPIKeys(mediaAPIKey: String, feedKey: String) {
        SecretVault.save(mediaAPIKey, account: "media-api-key")
        SecretVault.save(feedKey, account: "catalog-feed-key")
        guard !mediaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !feedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionStatus = "Both API keys are needed to load the catalog."
            return
        }
        isConnecting = true
        connectionStatus = "Loading movies and series…"
        Task { await refreshCatalog() }
    }

    func loadDetails(for item: MediaItem, forceRefresh: Bool = false) async -> MediaDetails? {
        guard item.isRemote else { return nil }
        if !forceRefresh,
           let cached = database.loadDetailsPayload(for: item.id),
           let details = await Self.parseDetailsData(cached.payload, for: item) {
            scheduleIMDbEnrichment(for: item, details: details)
            scheduleReferenceEnrichment(for: item, details: details)
            let refreshInterval: TimeInterval = details.hasPlayableResources ? 5 * 60 : 60
            if refreshStaleDetailsInBackground,
               Date().timeIntervalSince(cached.fetchedAt) >= refreshInterval {
                scheduleDetailsRefresh(for: item)
            }
            return details
        }

        guard let apiKey = SecretVault.read(account: "media-api-key"),
              !DirectMediaAPI.detailsURLs(for: item, apiKey: apiKey).isEmpty else { return nil }
        return await fetchDetails(for: item, apiKey: apiKey, reportFailure: true)
    }

    private func scheduleDetailsRefresh(for item: MediaItem) {
        guard !detailRefreshesInFlight.contains(item.id),
              let apiKey = SecretVault.read(account: "media-api-key"),
              !DirectMediaAPI.detailsURLs(for: item, apiKey: apiKey).isEmpty else { return }
        detailRefreshesInFlight.insert(item.id)
        Task { [weak self] in
            guard let self else { return }
            let refreshed = await self.fetchDetails(for: item, apiKey: apiKey, reportFailure: false)
            self.detailRefreshesInFlight.remove(item.id)
            if let refreshed {
                self.recentlyRefreshedDetails[item.id] = refreshed
                self.detailsRefreshRevision += 1
            }
        }
    }

    private func fetchDetails(for item: MediaItem, apiKey: String, reportFailure: Bool) async -> MediaDetails? {
        let response = try? await DirectMediaAPI.getJSONData(
            firstAcceptableFrom: DirectMediaAPI.detailsURLs(for: item, apiKey: apiKey),
            timeout: 12
        ) { data in
            let details = await Self.parseDetailsData(data, for: item)
            return DirectMediaAPI.JSONDataEvaluation(
                value: details,
                isPreferred: details?.hasPlayableResources == true,
                useAsFallback: details?.hasUsefulContent == true
            )
        }
        if let response {
            let details = response.value
            if details.hasPlayableResources {
                cacheDetailsPayload(response.data, for: item)
                scheduleIMDbEnrichment(for: item, details: details)
                scheduleReferenceEnrichment(for: item, details: details)
                return details
            }
            if details.hasUsefulContent {
                cacheDetailsPayload(response.data, for: item)
                scheduleIMDbEnrichment(for: item, details: details)
                scheduleReferenceEnrichment(for: item, details: details)
                return details
            }
        }
        if reportFailure && !Task.isCancelled {
            connectionStatus = "Details could not be loaded. Check the API key and connection."
        }
        return nil
    }

    private func cacheDetailsPayload(_ data: Data, for item: MediaItem) {
        database.saveDetailsPayload(data, for: item.id, fetchedAt: Date())
    }

    private func scheduleIMDbEnrichment(for item: MediaItem, details: MediaDetails) {
        guard IMDbMetadataStore.shared.isAvailable,
              imdbEnrichmentsInFlight.insert(item.id).inserted else { return }
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> (IMDbTitleMetadata?, MediaDetails) in
                guard let metadata = IMDbMediaEnricher.match(details, for: item) else { return (nil, details) }
                return (metadata, IMDbMediaEnricher.enrich(details, for: item, matched: metadata))
            }.value
            guard let self else { return }
            self.imdbEnrichmentsInFlight.remove(item.id)
            guard let metadata = result.0 else { return }
            let enriched = result.1
            self.database.saveIMDbMetadata(metadata, for: item.id)
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                let updatedItem = self.items[index].applyingIMDb(metadata)
                if updatedItem != self.items[index] {
                    self.items[index] = updatedItem
                    if let existingRating = self.personalRatings[item.id],
                       self.database.updatePersonalRatingSnapshot(updatedItem) {
                        self.personalRatings[item.id] = PersonalRating(
                            rating: existingRating.rating,
                            item: updatedItem,
                            updatedAt: existingRating.updatedAt
                        )
                    }
                }
            }
            if self.selectedItem?.id == item.id {
                self.selectedItem = self.selectedItem?.applyingIMDb(metadata)
            }
            self.recentlyRefreshedDetails[item.id] = enriched
            self.detailsRefreshRevision += 1
            self.scheduleReferenceEnrichment(for: item, details: enriched)
            if item.kind == "Series", let seriesID = enriched.imdbID {
                self.scheduleIMDbRecommendations(for: item, seriesID: seriesID)
            }
        }
    }

    private func scheduleReferenceEnrichment(for item: MediaItem, details: MediaDetails) {
        let imdbID = details.imdbID ?? item.imdbID
        guard item.kind == "Series" || item.kind == "Movie" else { return }
        let cached = database.loadReferenceMetadata(mediaID: item.id)
        if let cached { referenceMetadataByID[item.id] = cached }
        let tmdbToken = SecretVault.read(account: "tmdb-read-access-token")
        let hasTMDBToken = !(tmdbToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let forceTMDB = forceTMDBReferenceRefreshRequested
        forceTMDBReferenceRefreshRequested = false
        guard ReferenceMetadataService.shouldRefresh(cached, for: item, imdbID: imdbID,
                                                     hasTMDBToken: hasTMDBToken,
                                                     forceTMDB: forceTMDB) else {
            if let cached, !cached.isEmpty {
                recentlyRefreshedDetails[item.id] = ReferenceMetadataService.enrich(details, with: cached)
            }
            return
        }
        let lookupKey = "\(item.id)|\(imdbID ?? "series")"
        guard referenceMetadataLookupsInFlight.insert(lookupKey).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            let metadata = await ReferenceMetadataService.fetch(for: item, imdbID: imdbID, existing: cached,
                                                                tmdbToken: tmdbToken, forceTMDB: forceTMDB)
            self.referenceMetadataLookupsInFlight.remove(lookupKey)
            let latest = self.database.loadReferenceMetadata(mediaID: item.id)
            let combined = metadata.merging(latest ?? .empty())
            self.database.saveReferenceMetadata(combined, mediaID: item.id)
            self.referenceMetadataByID[item.id] = combined
            guard !combined.isEmpty else { return }
            self.recentlyRefreshedDetails[item.id] = ReferenceMetadataService.enrich(details, with: combined)
            self.detailsRefreshRevision += 1
        }
    }

    private func scheduleIMDbRecommendations(for item: MediaItem, seriesID: String) {
        guard imdbRecommendationsInFlight.insert(item.id).inserted else { return }
        Task { [weak self] in
            let recommendations = await Task.detached(priority: .background) {
                IMDbMetadataStore.shared.similarSeries(for: seriesID)
            }.value
            guard let self else { return }
            self.imdbRecommendationsInFlight.remove(item.id)
            guard let details = self.recentlyRefreshedDetails[item.id], details.imdbID == seriesID else { return }
            self.recentlyRefreshedDetails[item.id] = MediaDetails(
                description: details.description,
                year: details.year,
                rating: details.rating,
                runtime: details.runtime,
                genres: details.genres,
                country: details.country,
                director: details.director,
                cast: details.cast,
                sources: details.sources,
                downloadSources: details.downloadSources,
                seasons: details.seasons,
                imdbID: details.imdbID,
                imdbRating: details.imdbRating,
                imdbVotes: details.imdbVotes,
                similarSeries: recommendations,
                castPeople: details.castPeople,
                ratingSource: details.ratingSource,
                tagline: details.tagline,
                originalTitle: details.originalTitle,
                status: details.status,
                contentRating: details.contentRating,
                originalLanguage: details.originalLanguage,
                seasonCount: details.seasonCount,
                episodeCount: details.episodeCount,
                networks: details.networks,
                productionCompanies: details.productionCompanies,
                writers: details.writers,
                keywords: details.keywords,
                trailerURL: details.trailerURL,
                homepageURL: details.homepageURL,
                backdropURL: details.backdropURL
            )
            self.detailsRefreshRevision += 1
        }
    }

    func playRemoteSource(
        _ source: MediaStreamSource,
        title: String,
        item: MediaItem,
        episode: MediaEpisode?,
        details: MediaDetails? = nil
    ) {
        if activeWatchSessionID != nil {
            finishPlaybackSession(position: activeWatchProgress?.positionSeconds ?? 0,
                                  duration: activeWatchProgress?.durationSeconds)
        }
        activeRemotePlayback = (
            item: item,
            episodeID: episode?.id,
            episodeLabel: episode?.episodeLabel,
            episodeTitle: episode?.title,
            sourceTitle: source.title,
            details: details
        )
        playerTitle = title
        playerHeaders = source.headers
        playerURL = source.url
        playerRequestID = UUID()
    }

    var nextEpisodeTitle: String? { nextPlayableEpisode?.episode.title }

    @discardableResult
    func playNextEpisode() -> Bool {
        guard let next = nextPlayableEpisode else { return false }
        playRemoteSource(
            next.source,
            title: "\(next.item.title) · \(next.episode.title)",
            item: next.item,
            episode: next.episode,
            details: next.details
        )
        return true
    }

    private var nextPlayableEpisode: (
        item: MediaItem,
        episode: MediaEpisode,
        details: MediaDetails,
        source: MediaStreamSource
    )? {
        guard let active = activeRemotePlayback,
              active.item.kind == "Series",
              let details = active.details else { return nil }
        let episodes = details.seasons.flatMap(\.episodes)
        let currentIndex = active.episodeID.flatMap { id in episodes.firstIndex(where: { $0.id == id }) }
            ?? active.episodeLabel.flatMap { label in episodes.firstIndex(where: { $0.episodeLabel == label }) }
        guard let currentIndex else { return nil }
        for episode in episodes.dropFirst(currentIndex + 1) {
            if let source = (episode.sources + episode.downloadSources).first {
                return (active.item, episode, details, source)
            }
        }
        return nil
    }

    func startPlaybackSession(playerKind: String, localURL: URL? = nil) -> Double {
        if activeWatchSessionID != nil {
            finishPlaybackSession(position: activeWatchProgress?.positionSeconds ?? 0,
                                  duration: activeWatchProgress?.durationSeconds)
        }
        activeWatchPlayerKind = playerKind
        let progress: WatchProgress
        if let active = activeRemotePlayback {
            let stored = database.watchProgress(
                mediaID: active.item.id,
                episodeID: active.episodeID,
                episodeLabel: active.episodeLabel,
                episodeTitle: active.episodeTitle
            )
            let episode = active.details?.seasons.flatMap(\.episodes).first(where: { $0.id == active.episodeID })
                ?? active.details?.seasons.flatMap(\.episodes).first(where: { $0.episodeLabel == active.episodeLabel })
            let duration = episode.flatMap { Self.durationSeconds($0.duration) }
                ?? Self.durationSeconds(active.details?.runtime)
                ?? stored?.durationSeconds
            let resume = stored?.isWatched == true ? 0 : (stored?.positionSeconds ?? 0)
            progress = WatchProgress(
                mediaID: active.item.id,
                episodeID: stored?.episodeID ?? active.episodeID,
                mediaTitle: active.item.title,
                kind: active.item.kind,
                episodeTitle: active.episodeTitle,
                episodeLabel: active.episodeLabel,
                year: active.details?.year ?? active.item.year,
                artworkURL: episode?.artworkURL ?? active.item.artworkURL,
                imdbID: episode?.imdbID ?? active.details?.imdbID ?? active.item.imdbID,
                genres: active.details?.genres.isEmpty == false ? active.details!.genres : active.item.genres,
                positionSeconds: resume,
                durationSeconds: duration,
                watchedSeconds: stored?.watchedSeconds ?? 0,
                isWatched: false,
                updatedAt: Date()
            )
        } else {
            let url = localURL?.standardizedFileURL
            let mediaID = url.map { "local:\($0.path)" } ?? "local:\(playerTitle)"
            let stored = database.watchProgress(mediaID: mediaID, episodeID: nil)
            progress = WatchProgress(
                mediaID: mediaID,
                episodeID: nil,
                mediaTitle: playerTitle,
                kind: "Movie",
                episodeTitle: nil,
                episodeLabel: nil,
                year: "",
                artworkURL: nil,
                imdbID: nil,
                genres: [],
                positionSeconds: stored?.isWatched == true ? 0 : (stored?.positionSeconds ?? 0),
                durationSeconds: stored?.durationSeconds,
                watchedSeconds: stored?.watchedSeconds ?? 0,
                isWatched: false,
                updatedAt: Date()
            )
        }
        activeWatchProgress = progress
        activeWatchSessionID = database.beginWatchSession(progress: progress, playerKind: playerKind)
        refreshViewingData()
        return progress.positionSeconds
    }

    func playbackResumePosition(localURL: URL? = nil) -> Double {
        if let active = activeRemotePlayback {
            let stored = database.watchProgress(
                mediaID: active.item.id,
                episodeID: active.episodeID,
                episodeLabel: active.episodeLabel,
                episodeTitle: active.episodeTitle
            )
            return stored?.isWatched == true ? 0 : (stored?.positionSeconds ?? 0)
        }
        let url = localURL?.standardizedFileURL
        let mediaID = url.map { "local:\($0.path)" } ?? "local:\(playerTitle)"
        let stored = database.watchProgress(mediaID: mediaID, episodeID: nil)
        return stored?.isWatched == true ? 0 : (stored?.positionSeconds ?? 0)
    }

    func recordPlaybackProgress(position: Double, duration: Double?, watchedDelta: Double) {
        guard let sessionID = activeWatchSessionID, var progress = activeWatchProgress else { return }
        guard position.isFinite else { return }
        progress.positionSeconds = max(0, position)
        if let duration, duration.isFinite, duration > 0 { progress.durationSeconds = duration }
        progress.watchedSeconds += max(0, min(60, watchedDelta))
        if let total = progress.durationSeconds, total > 0 {
            if progress.positionSeconds / total >= 0.92 { progress.isWatched = true }
            else if progress.positionSeconds / total < 0.9 { progress.isWatched = false }
        }
        progress.updatedAt = Date()
        database.updateWatchSession(id: sessionID, progress: progress, watchedDelta: watchedDelta)
        activeWatchProgress = progress
        updateContinueWatching(with: progress)
    }

    func finishPlaybackSession(position: Double, duration: Double?) {
        guard let sessionID = activeWatchSessionID, var progress = activeWatchProgress else { return }
        if position.isFinite { progress.positionSeconds = max(0, position) }
        if let duration, duration.isFinite, duration > 0 { progress.durationSeconds = duration }
        if let total = progress.durationSeconds, total > 0, progress.positionSeconds / total >= 0.92 {
            progress.isWatched = true
        }
        progress.updatedAt = Date()
        database.updateWatchSession(id: sessionID, progress: progress, watchedDelta: 0, endedAt: Date())
        activeWatchSessionID = nil
        activeWatchProgress = nil
        refreshViewingData()
        invalidateViewingStats()
        invalidateRecommendations()
    }

    func monitorIINAPlayback(socketURL: URL) {
        guard let expectedSessionID = activeWatchSessionID else { return }
        iinaPlaybackMonitor?.stop()
        let monitor = IINAPlaybackMonitor(
            socketURL: socketURL,
            onProgress: { [weak self] position, duration, delta in
                Task { @MainActor [weak self] in
                    guard let self, self.activeWatchSessionID == expectedSessionID else { return }
                    self.recordPlaybackProgress(position: position, duration: duration, watchedDelta: delta)
                }
            },
            onFinished: { [weak self] position, duration in
                Task { @MainActor [weak self] in
                    guard let self, self.activeWatchSessionID == expectedSessionID else { return }
                    let saved = self.activeWatchProgress
                    let finalPosition = position > 0 ? position : (saved?.positionSeconds ?? position)
                    let finalDuration = duration ?? saved?.durationSeconds
                    self.finishPlaybackSession(position: finalPosition, duration: finalDuration)
                    self.iinaPlaybackMonitor = nil
                }
            }
        )
        iinaPlaybackMonitor = monitor
        monitor.start()
    }

    func setWatched(_ progress: WatchProgress, watched: Bool) {
        database.setWatched(progress, watched: watched)
        refreshViewingData()
        invalidateViewingStats()
        invalidateRecommendations()
    }

    func watchProgress(mediaID: String, episodeID: String?) -> WatchProgress? {
        database.watchProgress(mediaID: mediaID, episodeID: episodeID)
    }

    func isWatched(
        mediaID: String,
        episodeID: String?,
        episodeLabel: String? = nil,
        episodeTitle: String? = nil
    ) -> Bool {
        database.watchProgress(
            mediaID: mediaID,
            episodeID: episodeID,
            episodeLabel: episodeLabel,
            episodeTitle: episodeTitle
        )?.isWatched ?? false
    }

    func setWatched(item: MediaItem, episode: MediaEpisode?, details: MediaDetails?, watched: Bool) {
        let old = database.watchProgress(
            mediaID: item.id,
            episodeID: episode?.id,
            episodeLabel: episode?.episodeLabel,
            episodeTitle: episode?.title
        )
        let progress = WatchProgress(
            mediaID: item.id,
            episodeID: old?.episodeID ?? episode?.id,
            mediaTitle: item.title,
            kind: item.kind,
            episodeTitle: episode?.title,
            episodeLabel: episode?.episodeLabel,
            year: details?.year ?? item.year,
            artworkURL: episode?.artworkURL ?? item.artworkURL,
            imdbID: episode?.imdbID ?? details?.imdbID ?? item.imdbID,
            genres: details?.genres.isEmpty == false ? details!.genres : item.genres,
            positionSeconds: old?.positionSeconds ?? 0,
            durationSeconds: old?.durationSeconds ?? Self.durationSeconds(episode?.duration ?? details?.runtime),
            watchedSeconds: old?.watchedSeconds ?? 0,
            isWatched: watched,
            updatedAt: Date()
        )
        database.setWatched(progress, watched: watched)
        refreshViewingData()
        invalidateViewingStats()
        invalidateRecommendations()
    }

    func resume(_ progress: WatchProgress) async {
        guard !isResumingPlayback else { return }
        isResumingPlayback = true
        viewingUpdateMessage = nil
        defer { isResumingPlayback = false }

        if progress.mediaID.hasPrefix("local:") {
            let path = String(progress.mediaID.dropFirst("local:".count))
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                viewingUpdateMessage = "The file for this viewing session is no longer on this Mac."
                return
            }
            playLocalVideo(url, title: progress.displayTitle)
            return
        }
        let item = items.first(where: { $0.id == progress.mediaID })
            ?? database.loadCatalog().first(where: { $0.id == progress.mediaID })
        guard let item else {
            viewingUpdateMessage = "This title was not found in the saved catalog."
            return
        }
        func matchingEpisode(in details: MediaDetails?) -> MediaEpisode? {
            let episodes = details?.seasons.flatMap(\.episodes) ?? []
            return progress.episodeID.flatMap { id in episodes.first { $0.id == id } }
                ?? progress.episodeLabel.flatMap { label in episodes.first { $0.episodeLabel == label } }
                ?? progress.episodeTitle.flatMap { title in
                    episodes.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
                }
        }

        var details = await loadDetails(for: item)
        var episode = matchingEpisode(in: details)
        var sources = item.kind == "Series"
            ? ((episode?.sources ?? []) + (episode?.downloadSources ?? []))
            : ((details?.sources ?? []) + (details?.downloadSources ?? []))
        let cachedTitle = episode.map { "\(item.title) · \($0.title)" } ?? item.title
        if let offline = downloadManager.completedDownload(
            mediaItemID: item.id,
            episodeID: episode?.id ?? progress.episodeID,
            title: cachedTitle
        ) {
            playLocalVideo(offline, title: cachedTitle, item: item, episode: episode, details: details)
            return
        }
        let needsFreshDetails = sources.isEmpty || (item.kind == "Series" && episode == nil)
        if item.isRemote, needsFreshDetails,
           let refreshed = await loadDetails(for: item, forceRefresh: true) {
            let refreshedEpisode = matchingEpisode(in: refreshed)
            let refreshedSources = item.kind == "Series"
                ? ((refreshedEpisode?.sources ?? []) + (refreshedEpisode?.downloadSources ?? []))
                : (refreshed.sources + refreshed.downloadSources)
            if item.kind != "Series", !refreshedSources.isEmpty {
                details = refreshed
                sources = refreshedSources
            } else if let refreshedEpisode {
                details = refreshed
                episode = refreshedEpisode
                if !refreshedSources.isEmpty { sources = refreshedSources }
            }
        }
        if item.kind == "Series", (progress.episodeID != nil || progress.episodeLabel != nil || progress.episodeTitle != nil), episode == nil {
            viewingUpdateMessage = "The saved episode could not be matched in the refreshed season list."
            return
        }
        let title = episode.map { "\(item.title) · \($0.title)" } ?? item.title
        if let offline = downloadManager.completedDownload(
            mediaItemID: item.id,
            episodeID: episode?.id ?? progress.episodeID,
            title: title
        ) {
            playLocalVideo(offline, title: title, item: item, episode: episode, details: details)
            return
        }
        guard let source = sources.first else {
            viewingUpdateMessage = "No active playback source was found to resume this title."
            return
        }
        viewingUpdateMessage = nil
        playRemoteSource(source, title: title, item: item, episode: episode, details: details)
    }

    func resume(_ entry: WatchHistoryEntry) async {
        let saved = database.watchProgress(mediaID: entry.mediaID, episodeID: entry.episodeID)
        let progress = saved ?? WatchProgress(
            mediaID: entry.mediaID,
            episodeID: entry.episodeID,
            mediaTitle: entry.mediaTitle,
            kind: entry.kind,
            episodeTitle: entry.episodeTitle,
            episodeLabel: entry.episodeLabel,
            year: entry.year,
            artworkURL: entry.artworkURL,
            imdbID: entry.imdbID,
            genres: entry.genres,
            positionSeconds: entry.positionSeconds,
            durationSeconds: entry.durationSeconds,
            watchedSeconds: entry.watchedSeconds,
            isWatched: false,
            updatedAt: entry.startedAt
        )
        await resume(progress)
    }

    private static func durationSeconds(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        }
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = trimmed as NSString
        let matches = expression.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return Double(trimmed).map { $0 < 1000 ? $0 * 60 : $0 }
        }
        var total = 0.0
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: trimmed),
                  let unitRange = Range(match.range(at: 2), in: trimmed),
                  let number = Double(trimmed[numberRange]) else { continue }
            let unit = String(trimmed[unitRange])
            if unit.hasPrefix("h") { total += number * 3600 }
            else if unit.hasPrefix("m") { total += number * 60 }
            else { total += number }
        }
        return total > 0 ? total : nil
    }

    func activePlaybackSources(forceRefresh: Bool) async -> [MediaStreamSource] {
        guard let active = activeRemotePlayback else { return [] }
        let refreshed = forceRefresh ? await loadDetails(for: active.item, forceRefresh: true) : nil
        guard let details = refreshed ?? active.details else { return [] }
        activeRemotePlayback?.details = details
        recentlyRefreshedDetails[active.item.id] = details
        detailsRefreshRevision += 1

        let candidates: [MediaStreamSource]
        if active.item.kind == "Series" {
            let episodes = details.seasons.flatMap(\.episodes)
            let episode = episodes.first(where: { $0.id == active.episodeID })
                ?? episodes.first(where: { $0.episodeLabel == active.episodeLabel })
                ?? episodes.first(where: { $0.title.localizedCaseInsensitiveCompare(active.episodeTitle ?? "") == .orderedSame })
            candidates = (episode?.sources ?? []) + (episode?.downloadSources ?? [])
        } else {
            candidates = details.sources + details.downloadSources
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.url.absoluteString).inserted }
    }

    func useActivePlaybackSource(_ source: MediaStreamSource) {
        guard activeRemotePlayback != nil else { return }
        activeRemotePlayback?.sourceTitle = source.title
        playerHeaders = source.headers
        playerURL = source.url
    }

    var hasActiveRemotePlayback: Bool { activeRemotePlayback != nil }

    func refreshIMDbDataset() async {
        guard !isUpdatingIMDbDataset else { return }
        isUpdatingIMDbDataset = true
        defer { isUpdatingIMDbDataset = false }
        do {
            try await IMDbMetadataStore.shared.refresh { [weak self] message in
                Task { @MainActor in self?.imdbDatasetStatus = message }
            }
            let summary = await Task.detached(priority: .utility) {
                IMDbMetadataStore.shared.startupSummary()
            }.value
            let timestamp = summary.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "now"
            imdbDatasetStatus = "IMDb dataset ready · updated \(timestamp)"
            imdbChartLists = nil
            imdbPeopleAvailable = summary.hasPeopleData
            genreFacets = []
            recommendations = []
            if section == .genres { await loadGenreFacets() }
            if section == .forYou { await refreshDiscoveryData() }
            if section == .imdbCharts { await loadIMDbCharts() }
        } catch {
            imdbDatasetStatus = error.localizedDescription
        }
    }

    func loadIMDbCharts() async {
        guard !isLoadingIMDbCharts, imdbChartLists == nil else { return }
        isLoadingIMDbCharts = true
        defer { isLoadingIMDbCharts = false }
        imdbChartLists = await Task.detached(priority: .userInitiated) {
            IMDbMetadataStore.shared.chartLists()
        }.value
    }

    func refreshIMDbPeopleAvailability() {
        Task { @MainActor [weak self] in
            let available = await Task.detached(priority: .utility) {
                IMDbMetadataStore.shared.hasPeopleData()
            }.value
            self?.imdbPeopleAvailable = available
        }
    }

    func loadIMDbArtwork(for metadata: IMDbTitleMetadata) async -> Data? {
        let cache = database.cachedIMDbArtwork(for: metadata.tconst)
        if cache.cached { return cache.data }
        guard artworkLookupsInFlight.insert(metadata.tconst).inserted else { return nil }
        defer { artworkLookupsInFlight.remove(metadata.tconst) }

        let imageURL: URL?
        if let local = catalogTitle(matching: metadata), let artworkURL = local.artworkURL {
            imageURL = artworkURL
        } else if let apiKey = SecretVault.read(account: "media-api-key"),
                  let item = await searchSimbaTitle(matching: metadata, apiKey: apiKey) {
            imageURL = item.artworkURL
        } else {
            imageURL = nil
        }
        guard let imageURL else {
            if SecretVault.read(account: "media-api-key") != nil {
                database.saveIMDbArtwork(nil, sourceURL: nil, for: metadata.tconst)
            }
            return nil
        }

        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 20
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 8 * 1024 * 1024,
              let mimeType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
              mimeType.hasPrefix("image/"), NSImage(data: data) != nil else {
            database.saveIMDbArtwork(nil, sourceURL: imageURL.absoluteString, for: metadata.tconst)
            return nil
        }
        database.saveIMDbArtwork(data, sourceURL: imageURL.absoluteString, for: metadata.tconst)
        return data
    }

    func openCatalogTitle(matching metadata: IMDbTitleMetadata) async {
        similarTitleSearchMessage = nil
        if let candidate = catalogTitle(matching: metadata) {
            selectedItem = candidate
            return
        }
        guard resolvingSimilarTitleID == nil else { return }
        guard let apiKey = SecretVault.read(account: "media-api-key") else {
            similarTitleSearchMessage = "Add the Simba media API key in Settings to open this title."
            return
        }
        resolvingSimilarTitleID = metadata.id
        defer { resolvingSimilarTitleID = nil }
        guard let resolved = await searchSimbaTitle(matching: metadata, apiKey: apiKey) else {
            similarTitleSearchMessage = "Simba did not return a matching title for \(metadata.title)."
            return
        }
        database.saveRemoteItems([resolved])
        items = database.loadCatalog()
        selectedItem = items.first(where: { $0.id == resolved.id }) ?? resolved
        similarTitleSearchMessage = nil
    }

    func catalogTitle(matching metadata: IMDbTitleMetadata) -> MediaItem? {
        let targetTitle = normalizedMatchTitle(metadata.title)
        return items.compactMap { item -> (MediaItem, Double, Int)? in
            guard item.kind == metadata.kind else { return nil }
            let aliases = ([item.title] + item.matchingTitles).map(normalizedMatchTitle)
            let score = aliases.map { $0 == targetTitle ? 1.0 : matchTitleSimilarity(targetTitle, $0) }.max() ?? 0
            guard score >= 0.92 else { return nil }
            let yearDistance = metadata.year.flatMap { year in Int(item.year).map { abs($0 - year) } } ?? Int.max
            return (item, score, yearDistance)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.2 < rhs.2
        }.first?.0
    }

    private func searchSimbaTitle(matching metadata: IMDbTitleMetadata, apiKey: String) async -> MediaItem? {
        let target = normalizedMatchTitle(metadata.title)
        func matches(in payload: Any) -> [(MediaItem, Double, Int)] {
            Self.searchItems(from: payload, fallbackKind: metadata.kind)
                .filter { $0.kind == metadata.kind }
                .compactMap { item -> (MediaItem, Double, Int)? in
                    let titles = ([item.title] + item.matchingTitles).map(normalizedMatchTitle).filter { !$0.isEmpty }
                    let score = titles.map { $0 == target ? 1.0 : matchTitleSimilarity(target, $0) }.max() ?? 0
                    guard score >= 0.86 else { return nil }
                    let yearDistance = metadata.year.flatMap { imdbYear in
                        Int(item.year).map { abs($0 - imdbYear) }
                    } ?? Int.max
                    return (item, score, yearDistance)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return lhs.2 < rhs.2
                }
        }
        guard let payload = try? await DirectMediaAPI.getJSON(
            firstAcceptableFrom: DirectMediaAPI.searchURLs(query: metadata.title, routeKey: apiKey),
            timeout: 10,
            accepting: { !matches(in: $0).isEmpty }
        ) else { return nil }
        return matches(in: payload).first?.0
    }

    private func remapSeasons(_ seasons: [MediaSeason], imdbEpisodes: [IMDbEpisodeMetadata]) -> [MediaSeason] {
        IMDbEpisodeMatcher.remap(seasons, using: imdbEpisodes)
    }

    private func episodeNumberHint(_ label: String) -> (season: Int, episode: Int)? {
        let patterns = [
            #"(?i)S\s*\d+\s*E\s*\d+"#,
            #"(?i)\b\d+\s*[x×]\s*\d+\b"#,
            #"(?i)\bseason\s*\d+\s*(?:episode|ep)\s*\d+\b"#
        ]
        for pattern in patterns {
            guard let match = label.range(of: pattern, options: .regularExpression) else { continue }
            let values = label[match].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if values.count == 2 { return (values[0], values[1]) }
        }
        return nil
    }

    private func normalizedMatchTitle(_ value: String) -> String {
        MediaTitleMatching.normalize(value)
    }

    private func matchTitleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        MediaTitleMatching.similarity(lhs, rhs)
    }

    func searchRemote(_ query: String) {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        activeRemoteSearchID = requestID
        remoteSearchResults = []
        didFinishRemoteSearch = false
        isSearchingRemoteSearch = false
        guard !query.isEmpty else { return }
        guard section != .myRatings else {
            didFinishRemoteSearch = true
            return
        }

        isSearchingRemoteSearch = true
        searchTask = Task {
            defer {
                if activeRemoteSearchID == requestID { isSearchingRemoteSearch = false }
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, activeRemoteSearchID == requestID else { return }
            do {
                guard let apiKey = SecretVault.read(account: "media-api-key"),
                      let fallbackURL = DirectMediaAPI.searchFallbackURL(query: query) else {
                    throw DirectMediaAPIError.invalidURL
                }
                let resolvedPayload: Any
                if let payload = try? await DirectMediaAPI.getJSON(
                    firstAcceptableFrom: DirectMediaAPI.searchURLs(query: query, routeKey: apiKey),
                    timeout: 10,
                    accepting: { !Self.searchItems(from: $0).isEmpty }
                ) {
                    resolvedPayload = payload
                } else {
                    resolvedPayload = try await DirectMediaAPI.getJSON(url: fallbackURL, timeout: 10)
                }
                guard !Task.isCancelled, activeRemoteSearchID == requestID else { return }
                remoteSearchResults = Self.searchItems(from: resolvedPayload)
                database.saveRemoteItems(remoteSearchResults)
                didFinishRemoteSearch = true
            } catch {
                guard !Task.isCancelled, activeRemoteSearchID == requestID else { return }
                didFinishRemoteSearch = true
                connectionStatus = "Search is unavailable. Showing saved titles."
            }
        }
    }

    func refreshCatalog() async {
        guard !catalogRefreshInProgress else { return }
        guard SecretVault.read(account: "media-api-key") != nil else {
            connectionStatus = "Add the API key in Settings."
            return
        }
        catalogRefreshInProgress = true
        isConnecting = true
        defer {
            isConnecting = false
            catalogRefreshInProgress = false
        }

        guard let feedKey = SecretVault.read(account: "catalog-feed-key"),
              let movieURL = DirectMediaAPI.feedURL(filter: 0, page: 0, routeKey: feedKey),
              let seriesURL = DirectMediaAPI.feedURL(filter: 31, page: 0, routeKey: feedKey) else {
            connectionStatus = "Add the catalog feed key in Settings."
            return
        }

        // Fetch each catalog independently. A temporary failure in one feed must not
        // discard a successful response from the other feed or hide cached titles.
        async let movieResult = fetchCatalogRows(from: movieURL)
        async let seriesResult = fetchCatalogRows(from: seriesURL)
        let (movieResponse, seriesResponse) = await (movieResult, seriesResult)
        let movieRows = movieResponse.rows ?? []
        let seriesRows = seriesResponse.rows ?? []
        let movies = Self.mediaItems(from: movieRows, fallbackKind: "Movie", offset: 0)
        let series = Self.mediaItems(from: seriesRows, fallbackKind: "Series", offset: 0)
        let remoteItems = Self.uniqueItems(movies + series)
        guard !remoteItems.isEmpty else {
            let cached = database.loadCatalog()
            if !cached.isEmpty {
                items = cached
                connectionStatus = "Live catalog unavailable. Showing \(cached.filter { $0.kind == "Movie" }.count) saved movies and \(cached.filter { $0.kind == "Series" }.count) saved series."
            } else {
                let failures = [movieResponse.error, seriesResponse.error].compactMap { $0 }
                connectionStatus = failures.isEmpty
                    ? "The live API returned no movie or series titles."
                    : "Could not load the live catalog. Check the API settings and try Refresh."
            }
            return
        }

        database.saveRemoteItems(remoteItems)
        items = database.loadCatalog()
        catalogName = "Denbox API"
        nextMoviePage = 1
        nextSeriesPage = 1
        hasMoreMovies = movieRows.count >= DirectMediaAPI.pageSize
        hasMoreSeries = seriesRows.count >= DirectMediaAPI.pageSize
        let movieCount = items.filter { $0.kind == "Movie" }.count
        let seriesCount = items.filter { $0.kind == "Series" }.count
        if movieResponse.rows == nil || seriesResponse.rows == nil {
            let failedKind = movieResponse.rows == nil ? "movies" : "series"
            connectionStatus = "Live catalog loaded · \(movieCount) movies · \(seriesCount) series · \(failedKind) feed unavailable"
        } else {
            connectionStatus = "Live catalog · \(movieCount) movies · \(seriesCount) series"
        }
        section = .home
    }

    var canLoadMoreCatalog: Bool {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isLoadingMore else { return false }
        return switch section {
        case .home: hasMoreMovies || hasMoreSeries
        case .movies: hasMoreMovies
        case .shows: hasMoreSeries
        case .watchlist, .myRatings, .downloads, .imdbCharts, .releaseCalendar, .imdbPeople, .imdbFranchises,
             .forYou, .genres, .continueWatching, .watchHistory, .viewingStats: false
        }
    }

    func loadMoreCatalog() {
        guard canLoadMoreCatalog else { return }
        Task { await loadNextCatalogPage() }
    }

    private func loadNextCatalogPage() async {
        guard !isLoadingMore,
              let feedKey = SecretVault.read(account: "catalog-feed-key") else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let loadMovies = (section == .home || section == .movies) && hasMoreMovies
        let loadSeries = (section == .home || section == .shows) && hasMoreSeries
        var added = 0
        var failures = 0
        var fetched = 0
        let movieURL = loadMovies ? DirectMediaAPI.feedURL(filter: 0, page: nextMoviePage, routeKey: feedKey) : nil
        let seriesURL = loadSeries ? DirectMediaAPI.feedURL(filter: 31, page: nextSeriesPage, routeKey: feedKey) : nil
        async let movieResult = fetchCatalogPage(from: movieURL)
        async let seriesResult = fetchCatalogPage(from: seriesURL)
        let (movieResponse, seriesResponse) = await (movieResult, seriesResult)

        if let rows = movieResponse.rows {
            fetched += 1
            let pageItems = Self.mediaItems(from: rows, fallbackKind: "Movie", offset: nextMoviePage * DirectMediaAPI.pageSize)
            added += appendCatalogPage(pageItems, rawCount: rows.count, kind: "Movie")
            if !rows.isEmpty { nextMoviePage += 1 }
        } else if loadMovies {
            failures += 1
        }
        if let rows = seriesResponse.rows {
            fetched += 1
            let pageItems = Self.mediaItems(from: rows, fallbackKind: "Series", offset: nextSeriesPage * DirectMediaAPI.pageSize)
            added += appendCatalogPage(pageItems, rawCount: rows.count, kind: "Series")
            if !rows.isEmpty { nextSeriesPage += 1 }
        } else if loadSeries {
            failures += 1
        }

        if failures > 0 {
            connectionStatus = added > 0
                ? "Loaded \(added) titles; another catalog page failed. Retry to continue."
                : "Could not load the next page. Try again."
        } else if fetched == 0 {
            connectionStatus = "No more titles are available."
        } else {
            connectionStatus = "Loaded \(added) more titles · \(items.filter { $0.kind == "Movie" }.count) movies · \(items.filter { $0.kind == "Series" }.count) series"
        }
        if added > 0 {
        }
    }

    private func appendCatalogPage(_ pageItems: [MediaItem], rawCount: Int, kind: String) -> Int {
        var known = Set(items.map(\.id))
        let newItems = pageItems.filter { known.insert($0.id).inserted }
        let reachedEnd = rawCount == 0 || rawCount < DirectMediaAPI.pageSize
        if kind == "Movie" { hasMoreMovies = !reachedEnd }
        else { hasMoreSeries = !reachedEnd }
        if !newItems.isEmpty {
            database.saveRemoteItems(newItems)
            items.append(contentsOf: newItems)
        }
        return newItems.count
    }

    private func fetchCatalogRows(from url: URL) async -> (rows: [[String: Any]]?, error: Error?) {
        do {
            let payload = try await DirectMediaAPI.getJSON(url: url, timeout: 12)
            guard let rows = DirectMediaAPI.rows(from: payload) else {
                return (nil, DirectMediaAPIError.invalidResponse)
            }
            return (rows, nil)
        } catch {
            return (nil, error)
        }
    }

    private func fetchCatalogPage(from url: URL?) async -> (rows: [[String: Any]]?, error: Error?) {
        guard let url else { return (nil, nil) }
        return await fetchCatalogRows(from: url)
    }

    private static func uniqueItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func updateCatalog(with remoteItems: [MediaItem]) -> Bool {
        guard !remoteItems.isEmpty else { return false }
        var seenIDs = Set<String>()
        let uniqueItems = remoteItems.filter { seenIDs.insert($0.id).inserted }
        guard !uniqueItems.isEmpty else { return false }
        database.saveRemoteItems(uniqueItems)
        items = database.loadCatalog()
        catalogName = "Denbox API"
        let movieCount = uniqueItems.filter { $0.kind == "Movie" }.count
        let seriesCount = uniqueItems.filter { $0.kind == "Series" }.count
        connectionStatus = "Updated · \(movieCount) movies · \(seriesCount) series"
        section = .home
        return true
    }

    private static func homeItems(from payload: Any) -> [MediaItem] {
        let movieRows = DirectMediaAPI.rows(from: payload, key: "movies")
            ?? DirectMediaAPI.rows(from: payload, key: "movie")
            ?? DirectMediaAPI.rows(from: payload, key: "films")
            ?? []
        let seriesRows = DirectMediaAPI.rows(from: payload, key: "series")
            ?? DirectMediaAPI.rows(from: payload, key: "serie")
            ?? DirectMediaAPI.rows(from: payload, key: "shows")
            ?? DirectMediaAPI.rows(from: payload, key: "tv")
            ?? []

        if !movieRows.isEmpty || !seriesRows.isEmpty {
            let taggedMovies = movieRows.map { row -> [String: Any] in
                var row = row
                if row["type"] == nil { row["type"] = "movie" }
                return row
            }
            let taggedSeries = seriesRows.map { row -> [String: Any] in
                var row = row
                if row["type"] == nil { row["type"] = "series" }
                return row
            }
            let movies = mediaItems(from: taggedMovies, fallbackKind: "Movie", offset: 0)
            return movies + mediaItems(from: taggedSeries, fallbackKind: "Series", offset: movies.count)
        }

        guard let rows = DirectMediaAPI.rows(from: payload) else { return [] }
        let typedRows = rows.filter { row in
            let type = string(row["type"])?.lowercased() ?? ""
            return type.contains("movie") || type.contains("film") || type.contains("serie")
                || type.contains("series") || type == "tv"
        }
        return mediaItems(from: typedRows, fallbackKind: "Movie", offset: 0)
    }

    private static func mediaItems(from payload: Any, fallbackKind: String, offset: Int) -> [MediaItem] {
        guard let rows = DirectMediaAPI.rows(from: payload) else { return [] }
        return rows.enumerated().compactMap { index, row in
            let matchingTitles = titleAliases(from: row)
            guard let title = matchingTitles.first else { return nil }
            let apiID = string(row["id"]) ?? string(row["poster_id"]) ?? string(row["posted_id"])
                ?? string(row["external_id"]) ?? string(row["slug"]) ?? "\(fallbackKind.lowercased())-\(offset + index)"
            let apiKind = string(row["type"])?.lowercased() ?? ""
            let kind: String
            if apiKind.contains("serie") || apiKind.contains("series") || apiKind == "tv" {
                kind = "Series"
            } else if apiKind.contains("movie") || apiKind.contains("film") {
                kind = "Movie"
            } else {
                kind = fallbackKind
            }
            let id = "\(kind.lowercased()):\(apiID)"
            let year = string(row["year"]) ?? ""
            let artwork = string(row["image"]) ?? string(row["cover"]) ?? string(row["poster"])
                ?? string(row["slide"]) ?? string(row["backdrop"]) ?? string(row["thumbnail"])
                ?? string(row["poster_path"]) ?? string(row["thumb"])
            let artworkURL = artwork.flatMap(DirectMediaAPI.absoluteMediaURL)
            let description = string(row["description"]) ?? string(row["story"]) ?? ""
            let rating = string(row["imdb"]) ?? string(row["imdb_rating"]) ?? string(row["rating"])
            let subtitle = [year, rating.map { "★ \($0)" }, kind].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return MediaItem(
                id: id,
                apiID: apiID,
                title: title,
                subtitle: subtitle,
                synopsis: description,
                year: year,
                kind: kind,
                symbol: kind == "Series" ? "tv" : "film",
                palette: (offset + index) % 8,
                artworkURL: artworkURL,
                isRemote: true,
                matchingTitles: matchingTitles
            )
        }
    }

    private static func searchItems(from payload: Any, fallbackKind: String = "Movie") -> [MediaItem] {
        guard let rows = DirectMediaAPI.rows(from: payload) else { return [] }
        return rows.enumerated().compactMap { index, row in
            let matchingTitles = titleAliases(from: row)
            guard let title = matchingTitles.first else { return nil }
            let rawType = (string(row["type"]) ?? string(row["kind"]) ?? "").lowercased()
            let hasSeriesData = row["seasons"] != nil || row["episodes"] != nil || row["serie_id"] != nil
            let explicitlySeries = rawType.contains("serie") || rawType.contains("series") || rawType == "tv" || hasSeriesData
            let explicitlyMovie = rawType.contains("movie") || rawType.contains("film")
            let kind = explicitlySeries ? "Series" : (explicitlyMovie ? "Movie" : fallbackKind)
            var resolvedAPIID: String?
            for key in ["id", "poster_id", "posted_id", "serie_id", "series_id", "external_id", "slug"] where resolvedAPIID == nil {
                resolvedAPIID = string(row[key])
            }
            let apiID = resolvedAPIID ?? "search-\(index)-\(title)"
            let id = "\(kind.lowercased()):\(apiID)"
            let year = string(row["year"]) ?? ""
            return MediaItem(
                id: id,
                apiID: apiID,
                title: title,
                subtitle: [year, string(row["imdb"]).map { "★ \($0)" }, kind].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                synopsis: string(row["description"]) ?? "",
                year: year,
                kind: kind,
                symbol: kind == "Series" ? "tv" : "film",
                palette: index % 8,
                artworkURL: (string(row["image"]) ?? string(row["cover"]) ?? string(row["poster"]))
                    .flatMap(DirectMediaAPI.absoluteMediaURL),
                isRemote: true,
                matchingTitles: matchingTitles
            )
        }
    }

    private static func titleAliases(from row: [String: Any]) -> [String] {
        var result: [String] = []
        for key in ["title_en", "original_title", "title", "title_fa", "name", "poster_title"] {
            guard let value = string(row[key]),
                  !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { continue }
            result.append(value)
        }
        return result
    }

    nonisolated private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    nonisolated static func parseDetailsData(_ data: Data, for item: MediaItem) async -> MediaDetails? {
        await Task.detached(priority: .userInitiated) {
            guard let payload = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return nil
            }
            return Self.parseDetails(payload, for: item)
        }.value
    }

    nonisolated static func parseDetails(_ payload: Any, for item: MediaItem) -> MediaDetails {
        let detail = detailObject(payload, isSeries: item.kind == "Series")
        let description = string(detail["description"]) ?? string(detail["story"])
            ?? string(detail["overview"]) ?? string(detail["synopsis"])
        let year = string(detail["year"]) ?? item.year.nilIfEmpty
        let rating = string(detail["imdb"]) ?? string(detail["imdb_rating"])
            ?? string(detail["rating"])
        let runtime = string(detail["runtime"]) ?? string(detail["duration"])
            ?? string(detail["time"])
        let genres = stringList(detail["genres"] ?? detail["genre"])
        let cast = stringList(detail["actors"] ?? detail["cast"] ?? detail["actor"])
        let director = stringList(detail["directors"] ?? detail["director"]).joined(separator: ", ").nilIfEmpty
        let country = stringList(detail["countries"] ?? detail["country"]).joined(separator: ", ").nilIfEmpty
        return MediaDetails(
            description: description,
            year: year,
            rating: rating,
            runtime: runtime,
            genres: genres,
            country: country,
            director: director,
            cast: cast,
            sources: streamSources(from: detail),
            downloadSources: streamSources(from: detail, includeDownloadFields: true),
            seasons: item.kind == "Series" ? parseSeasons(from: detail) : [],
            imdbID: nil,
            imdbRating: nil,
            imdbVotes: nil,
            similarSeries: []
        )
    }

    nonisolated private static func detailObject(_ payload: Any, isSeries: Bool) -> [String: Any] {
        if let object = payload as? [String: Any] {
            for key in ["data", "result", "message", "details", "movie", "serie", "series", "poster", "item"] {
                if let nested = object[key] as? [String: Any] {
                    return detailObject(nested, isSeries: isSeries)
                }
                if let nested = object[key] as? [Any] {
                    return isSeries ? ["seasons": nested] : ["sources": nested]
                }
            }
            return object
        }
        if let rows = payload as? [Any] {
            return isSeries ? ["seasons": rows] : ["sources": rows]
        }
        return [:]
    }

    nonisolated private static func stringList(_ value: Any?) -> [String] {
        guard let value, !(value is NSNull) else { return [] }
        if let value = string(value) { return [value] }
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            if let value = string(row) { return value }
            guard let object = row as? [String: Any] else { return nil }
            return string(object["name"]) ?? string(object["title"]) ?? string(object["title_fa"])
        }
    }

    nonisolated private static func parseSeasons(from detail: [String: Any]) -> [MediaSeason] {
        let rawSeasons = detail["seasons"] ?? detail["episodes"] ?? detail["sources"]
        guard let rows = rawSeasons as? [Any] else { return [] }
        let hasSeasonWrappers = rows.contains { value in
            guard let object = value as? [String: Any] else { return false }
            return object["episodes"] != nil || object["season_number"] != nil
                || object["season"] != nil || string(object["title"])?.localizedCaseInsensitiveContains("season") == true
        }
        let normalizedRows: [Any]
        if detail["seasons"] == nil && !hasSeasonWrappers {
            normalizedRows = [["title": "Season 1", "episodes": rows]]
        } else {
            normalizedRows = rows
        }
        var result: [MediaSeason] = []
        for (seasonIndex, value) in normalizedRows.enumerated() {
            let seasonObject = value as? [String: Any] ?? ["episodes": [value]]
            let rawEpisodes = seasonObject["episodes"] ?? seasonObject["sources"]
                ?? seasonObject["parts"] ?? seasonObject["playas"]
            let episodeRows = rawEpisodes as? [Any] ?? [value]
            var episodes: [MediaEpisode] = []
            for (episodeIndex, episodeValue) in episodeRows.enumerated() {
                let episode = episodeValue as? [String: Any] ?? ["url": episodeValue]
                let sources = streamSources(from: ["sources": episode])
                let downloadSources = streamSources(from: ["sources": episode], includeDownloadFields: true)
                guard !sources.isEmpty || !downloadSources.isEmpty else { continue }
                let number = integer(episode["episode_number"] ?? episode["number"] ?? episode["episode"])
                    ?? episodeIndex + 1
                var matchingTitles: [String] = []
                for key in ["title_en", "english_title", "original_title", "originalTitle", "name", "title", "title_fa"] {
                    if let alias = string(episode[key]) { matchingTitles.append(alias) }
                }
                let episodeTitle = matchingTitles.first ?? "Episode \(number)"
                let synopsis = string(episode["description"]) ?? string(episode["story"])
                    ?? string(episode["overview"]) ?? ""
                let artwork = string(episode["image"]) ?? string(episode["poster"])
                    ?? string(episode["cover"])
                episodes.append(MediaEpisode(
                    id: string(episode["id"]) ?? "s\(seasonIndex + 1)e\(number)-\(episodeTitle)",
                    title: episodeTitle,
                    episodeLabel: String(format: "S%02dE%02d", integer(seasonObject["season_number"] ?? seasonObject["number"]) ?? seasonIndex + 1, number),
                    synopsis: synopsis,
                    duration: string(episode["duration"]) ?? string(episode["runtime"]),
                    artworkURL: artwork.flatMap(DirectMediaAPI.absoluteMediaURL),
                    sources: sources,
                    downloadSources: downloadSources,
                    imdbRating: nil,
                    imdbVotes: nil,
                    matchingTitles: matchingTitles
                ))
            }
            guard !episodes.isEmpty else { continue }
            let number = integer(seasonObject["season_number"] ?? seasonObject["number"]) ?? seasonIndex + 1
            result.append(MediaSeason(
                id: string(seasonObject["id"]) ?? "season-\(number)",
                title: string(seasonObject["title"]) ?? string(seasonObject["name"]) ?? "Season \(number)",
                episodes: episodes
            ))
        }
        return result
    }

    nonisolated private static func streamSources(from value: Any, includeDownloadFields: Bool = false) -> [MediaStreamSource] {
        let playableExtensions: Set<String> = ["m3u8", "mp4", "m4v", "mkv", "mov", "webm", "mpd", "mpeg", "mpg", "ts", "avi", "flv"]
        let excludedExtensions: Set<String> = ["srt", "vtt", "ass", "ssa", "sub", "jpg", "jpeg", "png", "webp", "gif", "zip", "rar", "pdf"]
        let sourceContainers: Set<String> = includeDownloadFields
            ? ["sources", "links", "playas", "streams", "play", "downloads", "downloadas", "download_links"]
            : ["sources", "links", "playas", "streams", "play"]
        var result: [MediaStreamSource] = []
        var seen = Set<String>()

        func add(_ raw: String, row: [String: Any], key: String, inSourceList: Bool) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
            let candidate = URL(string: normalized)
            let hasWebScheme = ["http", "https"].contains(candidate?.scheme?.lowercased() ?? "")
            let looksRelative = normalized.hasPrefix("/") || normalized.contains("/")
                || playableExtensions.contains(candidate?.pathExtension.lowercased() ?? "")
            guard hasWebScheme || looksRelative else { return }
            guard let url = DirectMediaAPI.absoluteMediaURL(normalized), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty else { return }
            let pathExtension = url.pathExtension.lowercased()
            guard !excludedExtensions.contains(pathExtension) else { return }
            let explicitPlaybackKey = ["play_url", "stream_url", "video_url", "hls", "mp4", "src"].contains(key)
                || (includeDownloadFields && ["download_url", "downloadas", "download"].contains(key))
            guard explicitPlaybackKey || inSourceList || playableExtensions.contains(pathExtension) else { return }
            guard seen.insert(url.absoluteString).inserted else { return }

            var headers: [String: String] = [:]
            if let rawHeaders = row["headers"] as? [String: Any] {
                let allowed = Set(["user-agent", "referer", "origin", "authorization", "cookie"])
                for (name, value) in rawHeaders {
                    if allowed.contains(name.lowercased()), let text = string(value) {
                        headers[name] = text
                    }
                }
            }
            let label = string(row["quality"]) ?? string(row["label"])
                ?? string(row["title"]) ?? string(row["name"])
            result.append(MediaStreamSource(
                id: url.absoluteString,
                title: label ?? "Source \(result.count + 1)",
                url: url,
                headers: headers
            ))
        }

        func walk(_ node: Any, inSourceList: Bool) {
            if let object = node as? [String: Any] {
                let linkKeys = includeDownloadFields
                    ? ["play_url", "stream_url", "video_url", "hls", "mp4", "url", "link", "src", "download_url", "downloadas", "download"]
                    : ["play_url", "stream_url", "video_url", "hls", "mp4", "url", "link", "src"]
                for key in linkKeys {
                    if let raw = string(object[key]) { add(raw, row: object, key: key, inSourceList: inSourceList) }
                }
                for (key, nested) in object where sourceContainers.contains(key.lowercased()) {
                    walk(nested, inSourceList: true)
                }
                for key in ["seasons", "episodes", "data", "result", "message", "details", "movie", "serie", "series"] {
                    if let nested = object[key] { walk(nested, inSourceList: inSourceList) }
                }
            } else if let rows = node as? [Any] {
                for row in rows { walk(row, inSourceList: inSourceList) }
            } else if inSourceList, let raw = string(node) {
                add(raw, row: [:], key: "url", inSourceList: true)
            }
        }

        walk(value, inSourceList: false)
        return result
    }

    nonisolated private static func integer(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    func openLocalVideo() {
        let panel = NSOpenPanel()
        panel.title = "Choose a video"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        playLocalVideo(url, title: url.deletingPathExtension().lastPathComponent)
    }

    func playLocalVideo(_ url: URL, title: String, item: MediaItem? = nil, episode: MediaEpisode? = nil, details: MediaDetails? = nil) {
        if activeWatchSessionID != nil {
            finishPlaybackSession(position: activeWatchProgress?.positionSeconds ?? 0,
                                  duration: activeWatchProgress?.durationSeconds)
        }
        if let item {
            activeRemotePlayback = (
                item: item,
                episodeID: episode?.id,
                episodeLabel: episode?.episodeLabel,
                episodeTitle: episode?.title,
                sourceTitle: nil,
                details: details
            )
        } else {
            activeRemotePlayback = nil
        }
        playerTitle = title
        playerHeaders = [:]
        playerURL = url
        playerRequestID = UUID()
    }

    func importCatalog() {
        let panel = NSOpenPanel()
        panel.title = "Import a catalog JSON file"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ImportedCatalog.self, from: data) else { return }

        var records: [(ImportedItem, String?)] = []
        records.append(contentsOf: (decoded.items ?? []).map { ($0, nil) })
        records.append(contentsOf: (decoded.movies ?? []).map { ($0, "Movie") })
        records.append(contentsOf: (decoded.series ?? []).map { ($0, "Series") })
        records.append(contentsOf: (decoded.posters ?? []).map { ($0, nil) })
        guard !records.isEmpty else { return }
        items = records.enumerated().map { index, entry in
            let (record, fallbackKind) = entry
            let kindValue = (record.type ?? fallbackKind ?? "Movie").lowercased()
            let kind = kindValue.contains("series") || kindValue.contains("show") || kindValue.contains("serie") ? "Series" : "Movie"
            return MediaItem(
                id: record.id ?? "imported-\(index)-\(record.title)",
                title: record.title,
                subtitle: kind == "Series" ? "Series" : "Feature film",
                synopsis: record.synopsis ?? record.description ?? "Imported from your catalog file.",
                year: record.year ?? "",
                kind: kind,
                symbol: kind == "Series" ? "tv" : "film",
                palette: index % 8
            )
        }
        catalogName = url.deletingPathExtension().lastPathComponent
        database.saveLocalItems(items)
        items = database.loadCatalog()
        section = .home
        searchText = ""
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private enum DirectMediaAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The API URL is invalid."
        case .invalidResponse: "The server returned an invalid response."
        case .server(let message): message
        }
    }
}

enum DirectMediaAPI {
    static let pageSize = 30
    private static let feedHost = "https://rubyxpin.info"
    // Current HTTPS origin advertised by the APK's config endpoint.
    private static let apkAPIBase = "https://ninwinios.info/api"
    private static let knownMediaHost = "https://gitcss.info"
    private static let searchHost = "https://gitcss.info/api-user/newapi/like.php"

    private struct RouteResponse: Sendable {
        let data: Data?
        let statusCode: Int?
        let error: String?
    }

    struct JSONDataEvaluation<Value: Sendable>: Sendable {
        let value: Value?
        let isPreferred: Bool
        let useAsFallback: Bool
    }

    static func feedURL(filter: Int, page: Int, routeKey: String) -> URL? {
        let key = pathComponent(routeKey)
        return URL(string: "\(feedHost)/api/poster/by/filtres/\(filter)/0/created/\(max(0, page))/\(key)/")
    }

    static func homeURLs(routeKey: String) -> [URL] {
        let key = pathComponent(routeKey)
        return [URL(string: "\(apkAPIBase)/first/\(key)/"),
                URL(string: "\(knownMediaHost)/api/first/\(key)/")].compactMap { $0 }
    }

    static func detailsURLs(for item: MediaItem, apiKey: String) -> [URL] {
        let key = pathComponent(apiKey)
        let itemID = pathComponent(item.apiID ?? item.id)
        let path = item.kind == "Series"
            ? "/api/season/by/serie/\(itemID)/\(key)/"
            : "/api/movie/by/\(itemID)/\(key)/"
        let apkPath = path.replacingOccurrences(of: "/api/", with: "/")
        return [URL(string: apkAPIBase + apkPath), URL(string: knownMediaHost + path)].compactMap { $0 }
    }

    static func searchURLs(query: String, routeKey: String) -> [URL] {
        let query = pathComponent(query)
        let key = pathComponent(routeKey)
        return [URL(string: "\(apkAPIBase)/search/\(query)/\(key)/"),
                URL(string: "\(knownMediaHost)/api/search/\(query)/\(key)/")].compactMap { $0 }
    }

    static func searchFallbackURL(query: String) -> URL? {
        var components = URLComponents(string: searchHost)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "search-movie"),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }

    static func absoluteMediaURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: value, relativeTo: URL(string: feedHost))?.absoluteURL
    }

    static func rows(from payload: Any) -> [[String: Any]]? {
        if let rows = payload as? [[String: Any]] { return rows }
        guard let object = payload as? [String: Any] else { return nil }
        var emptyRows: [[String: Any]]?
        for key in ["posters", "movies", "movie", "series", "serie", "slides", "films", "shows", "tv", "results", "items", "data", "message", "home", "response", "payload"] {
            if let rows = object[key] as? [[String: Any]] {
                if !rows.isEmpty { return rows }
                if emptyRows == nil { emptyRows = rows }
            }
            if let nested = object[key] as? [String: Any], let rows = rows(from: nested) {
                if !rows.isEmpty { return rows }
                if emptyRows == nil { emptyRows = rows }
            }
        }
        if object["title"] != nil || object["title_fa"] != nil { return [object] }
        return emptyRows
    }

    static func rows(from payload: Any, key: String) -> [[String: Any]]? {
        guard let object = payload as? [String: Any] else { return nil }
        if let rows = object[key] as? [[String: Any]] { return rows }
        for wrapper in ["data", "result", "message", "home", "response", "payload"] {
            if let nested = object[wrapper] as? [String: Any],
               let rows = rows(from: nested, key: key) { return rows }
        }
        return nil
    }

    @MainActor
    static func getJSON(url: URL, timeout: TimeInterval = 25) async throws -> Any {
        try await getJSON(firstAcceptableFrom: [url], timeout: timeout, accepting: { _ in true })
    }

    @MainActor
    static func getJSON(
        firstAcceptableFrom urls: [URL],
        timeout: TimeInterval,
        accepting: (Any) -> Bool
    ) async throws -> Any {
        guard !urls.isEmpty else { throw DirectMediaAPIError.invalidURL }
        var lastError = "No route returned usable JSON."
        let payload = await withTaskGroup(of: RouteResponse.self, returning: Any?.self) { group in
            for url in urls {
                group.addTask { await fetchJSON(url: url, timeout: timeout) }
            }
            while let response = await group.next() {
                guard let data = response.data else {
                    lastError = response.error ?? lastError
                    continue
                }
                guard let statusCode = response.statusCode, (200..<300).contains(statusCode) else {
                    lastError = response.statusCode.map { "HTTP \($0)" } ?? lastError
                    continue
                }
                guard let candidate = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                    lastError = "The server returned invalid JSON."
                    continue
                }
                if accepting(candidate) {
                    group.cancelAll()
                    return candidate
                }
                lastError = "The server returned no matching titles."
            }
            return nil
        }
        guard let payload else { throw DirectMediaAPIError.server(lastError) }
        return payload
    }

    @MainActor
    static func getJSONData<Value: Sendable>(
        firstAcceptableFrom urls: [URL],
        timeout: TimeInterval,
        evaluating: @escaping @Sendable (Data) async -> JSONDataEvaluation<Value>
    ) async throws -> (data: Data, value: Value) {
        guard !urls.isEmpty else { throw DirectMediaAPIError.invalidURL }
        var lastError = "No route returned usable JSON."
        let payload: (Data, Value)? = await withTaskGroup(of: RouteResponse.self, returning: (Data, Value)?.self) { group in
            for url in urls {
                group.addTask { await fetchJSON(url: url, timeout: timeout) }
            }
            var fallback: (Data, Value)?
            while let response = await group.next() {
                guard let data = response.data else {
                    lastError = response.error ?? lastError
                    continue
                }
                guard let statusCode = response.statusCode, (200..<300).contains(statusCode) else {
                    lastError = response.statusCode.map { "HTTP \($0)" } ?? lastError
                    continue
                }
                let evaluation = await evaluating(data)
                guard let value = evaluation.value else {
                    lastError = "The server returned invalid JSON."
                    continue
                }
                if evaluation.isPreferred {
                    group.cancelAll()
                    return (data, value)
                }
                if evaluation.useAsFallback, fallback == nil {
                    fallback = (data, value)
                }
            }
            return fallback
        }
        guard let payload else { throw DirectMediaAPIError.server(lastError) }
        return (payload.0, payload.1)
    }

    private static func fetchJSON(url: URL, timeout: TimeInterval) async -> RouteResponse {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return RouteResponse(data: nil, statusCode: nil, error: "The server returned an invalid response.")
            }
            return RouteResponse(data: data, statusCode: http.statusCode, error: nil)
        } catch {
            return RouteResponse(data: nil, statusCode: nil, error: error.localizedDescription)
        }
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private enum SecretVault {
    private static let service = "com.sepehr.SimbaMac.media-api"
    private static let bootstrapMigration: Void = {
        guard
            let url = Bundle.main.url(forResource: "DenboxPrivateAPIKeys", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return }

        let version = values["_version"] ?? "1"
        let markerAccount = "bundle-bootstrap-\(version)"
        guard readStored(account: markerAccount) == nil else { return }

        for (account, token) in values where account != "_version" {
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  readStored(account: account) == nil else { continue }
            save(token, account: account)
        }

        save("complete", account: markerAccount)
    }()

    static func read(account: String) -> String? {
        _ = bootstrapMigration
        return readStored(account: account)
    }

    private static func readStored(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return token
    }

    static func save(_ token: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var entry = query
        entry[kSecValueData as String] = Data(token.utf8)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(entry as CFDictionary, nil)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct DownloadedMedia: Identifiable {
    let id: String
    let title: String
    let sourceTitle: String
    let fileURL: URL
    let byteCount: Int64
    let segmentCount: Int
    let createdAt: Date
    let catalogMediaID: String?
    let episodeID: String?
}

struct CatalogMetadataPayloads: Sendable {
    var references: [String: Data] = [:]
    var publicTitles: [String: [Data]] = [:]
    var publicAttempts: [String: [String: Date]] = [:]
}

private struct CachedCatalogMetadata: Sendable {
    let reference: ReferenceTitleMetadata?
    let publicTitles: [PublicTitleMetadata]
    let publicAttempts: [String: Date]
}

final class MediaDatabase {
    private var handle: OpaquePointer?
    private let databasePath: String

    init(databaseURL: URL? = nil) {
        let dbURL: URL
        if let databaseURL {
            try? FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            dbURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("Simba", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            dbURL = directory.appendingPathComponent("library.sqlite")
        }
        databasePath = dbURL.path
        guard sqlite3_open(dbURL.path, &handle) == SQLITE_OK else { return }
        sqlite3_busy_timeout(handle, 5000)
        execute("""
            CREATE TABLE IF NOT EXISTS media (
            id TEXT PRIMARY KEY,
            api_id TEXT,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            synopsis TEXT NOT NULL,
            year TEXT NOT NULL,
            kind TEXT NOT NULL,
            symbol TEXT NOT NULL,
            palette INTEGER NOT NULL,
            artwork_url TEXT,
            source TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS saved_items (
            media_id TEXT PRIMARY KEY,
            saved_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS personal_ratings (
            media_id TEXT PRIMARY KEY,
            rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5),
            item_payload TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS media_details_cache (
            media_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            fetched_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS imdb_artwork_cache (
            tconst TEXT PRIMARY KEY,
            image_data BLOB,
            source_url TEXT,
            cached_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS imdb_media_metadata (
            media_id TEXT PRIMARY KEY,
            imdb_id TEXT,
            genres TEXT NOT NULL DEFAULT '[]',
            rating TEXT,
            votes INTEGER
        );
        CREATE TABLE IF NOT EXISTS downloaded_media (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            source_title TEXT NOT NULL DEFAULT '',
            file_path TEXT NOT NULL,
            byte_count INTEGER NOT NULL,
            segment_count INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            catalog_media_id TEXT,
            episode_id TEXT
        );
        CREATE TABLE IF NOT EXISTS watch_progress (
            media_id TEXT NOT NULL,
            episode_id TEXT NOT NULL DEFAULT '',
            media_title TEXT NOT NULL,
            kind TEXT NOT NULL,
            episode_title TEXT,
            episode_label TEXT,
            year TEXT NOT NULL DEFAULT '',
            artwork_url TEXT,
            imdb_id TEXT,
            genres TEXT NOT NULL DEFAULT '[]',
            position_seconds REAL NOT NULL DEFAULT 0,
            duration_seconds REAL,
            watched_seconds REAL NOT NULL DEFAULT 0,
            is_watched INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL,
            PRIMARY KEY(media_id, episode_id)
        );
        CREATE TABLE IF NOT EXISTS watch_sessions (
            id TEXT PRIMARY KEY,
            media_id TEXT NOT NULL,
            episode_id TEXT NOT NULL DEFAULT '',
            media_title TEXT NOT NULL,
            kind TEXT NOT NULL,
            episode_title TEXT,
            episode_label TEXT,
            year TEXT NOT NULL DEFAULT '',
            artwork_url TEXT,
            imdb_id TEXT,
            genres TEXT NOT NULL DEFAULT '[]',
            started_at REAL NOT NULL,
            position_seconds REAL NOT NULL DEFAULT 0,
            duration_seconds REAL,
            watched_seconds REAL NOT NULL DEFAULT 0,
            player_kind TEXT NOT NULL,
            ended_at REAL
        );
        CREATE TABLE IF NOT EXISTS genre_preferences (
            category TEXT NOT NULL,
            genre TEXT NOT NULL,
            PRIMARY KEY(category, genre)
        );
        CREATE TABLE IF NOT EXISTS public_title_metadata (
            media_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            payload TEXT NOT NULL,
            imported_at REAL NOT NULL,
            PRIMARY KEY(media_id, provider)
        );
        CREATE TABLE IF NOT EXISTS localized_media_titles (
            media_id TEXT PRIMARY KEY,
            english_title TEXT NOT NULL DEFAULT '',
            persian_title TEXT NOT NULL,
            provider TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS public_title_metadata_attempts (
            media_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            attempted_at REAL NOT NULL,
            lookup_version INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY(media_id, provider)
        );
        CREATE TABLE IF NOT EXISTS reference_metadata_cache (
            media_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            fetched_at REAL NOT NULL
        );
        """)
        if !columnExists("segment_count", in: "downloaded_media") {
            execute("ALTER TABLE downloaded_media ADD COLUMN segment_count INTEGER NOT NULL DEFAULT 1")
        }
        if !columnExists("catalog_media_id", in: "downloaded_media") {
            execute("ALTER TABLE downloaded_media ADD COLUMN catalog_media_id TEXT")
        }
        if !columnExists("episode_id", in: "downloaded_media") {
            execute("ALTER TABLE downloaded_media ADD COLUMN episode_id TEXT")
        }
        if !columnExists("source_title", in: "downloaded_media") {
            execute("ALTER TABLE downloaded_media ADD COLUMN source_title TEXT NOT NULL DEFAULT ''")
        }
        if !columnExists("lookup_version", in: "public_title_metadata_attempts") {
            execute("ALTER TABLE public_title_metadata_attempts ADD COLUMN lookup_version INTEGER NOT NULL DEFAULT 1")
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func loadPublicTitleMetadata(mediaID: String, provider: PublicMetadataProvider) -> PublicTitleMetadata? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM public_title_metadata WHERE media_id=? AND provider=? LIMIT 1"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        bind(provider.rawValue, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let payload = columnText(statement, 0),
              let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PublicTitleMetadata.self, from: data)
    }

    func loadLocalizedPersianTitle(mediaID: String) -> String? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT persian_title FROM localized_media_titles WHERE media_id=? LIMIT 1",
                                 -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return columnText(statement, 0)
    }

    func saveLocalizedPersianTitle(
        _ persianTitle: String,
        englishTitle: String,
        provider: PublicMetadataProvider,
        mediaID: String
    ) {
        guard let handle else { return }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO localized_media_titles(media_id,english_title,persian_title,provider,updated_at)
        VALUES(?,?,?,?,?)
        ON CONFLICT(media_id) DO UPDATE SET
            english_title=excluded.english_title,
            persian_title=excluded.persian_title,
            provider=excluded.provider,
            updated_at=excluded.updated_at
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        bind(englishTitle, at: 2, in: statement)
        bind(persianTitle, at: 3, in: statement)
        bind(provider.rawValue, at: 4, in: statement)
        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func savePublicTitleMetadata(_ metadata: PublicTitleMetadata, for mediaID: String) -> Bool {
        guard let handle,
              let data = try? JSONEncoder().encode(metadata),
              let payload = String(data: data, encoding: .utf8) else { return false }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO public_title_metadata(media_id,provider,payload,imported_at) VALUES(?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        bind(metadata.provider.rawValue, at: 2, in: statement)
        bind(payload, at: 3, in: statement)
        sqlite3_bind_double(statement, 4, metadata.importedAt.timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    func publicTitleMetadataLastAttempt(mediaID: String, provider: PublicMetadataProvider) -> Date? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        let sql = "SELECT attempted_at,lookup_version FROM public_title_metadata_attempts WHERE media_id=? AND provider=? LIMIT 1"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        bind(provider.rawValue, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_int(statement, 1) == Int32(PublicTitleMetadataRefreshPolicy.lookupVersion) else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
    }

    func recordPublicTitleMetadataAttempt(mediaID: String, provider: PublicMetadataProvider, at date: Date = Date()) {
        guard let handle else { return }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO public_title_metadata_attempts(media_id,provider,attempted_at,lookup_version) VALUES(?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        bind(provider.rawValue, at: 2, in: statement)
        sqlite3_bind_double(statement, 3, date.timeIntervalSince1970)
        sqlite3_bind_int(statement, 4, Int32(PublicTitleMetadataRefreshPolicy.lookupVersion))
        sqlite3_step(statement)
    }

    func loadReferenceMetadata(mediaID: String) -> ReferenceTitleMetadata? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM reference_metadata_cache WHERE media_id=? LIMIT 1"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let payload = columnText(statement, 0),
              let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReferenceTitleMetadata.self, from: data)
    }

    func loadCatalogMetadataPayloads(for mediaIDs: Set<String>) -> CatalogMetadataPayloads {
        guard let handle, !mediaIDs.isEmpty else { return CatalogMetadataPayloads() }
        var result = CatalogMetadataPayloads()
        let ids = mediaIDs.sorted()
        let chunkSize = 500

        for lowerBound in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[lowerBound..<min(lowerBound + chunkSize, ids.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")

            var referenceStatement: OpaquePointer?
            let referenceSQL = "SELECT media_id,payload FROM reference_metadata_cache WHERE media_id IN (\(placeholders))"
            if sqlite3_prepare_v2(handle, referenceSQL, -1, &referenceStatement, nil) == SQLITE_OK,
               let referenceStatement {
                defer { sqlite3_finalize(referenceStatement) }
                for (index, mediaID) in chunk.enumerated() {
                    bind(mediaID, at: Int32(index + 1), in: referenceStatement)
                }
                while sqlite3_step(referenceStatement) == SQLITE_ROW {
                    guard let mediaID = columnText(referenceStatement, 0),
                          let payload = columnText(referenceStatement, 1),
                          let data = payload.data(using: .utf8) else { continue }
                    result.references[mediaID] = data
                }
            }

            var publicStatement: OpaquePointer?
            let publicSQL = "SELECT media_id,payload FROM public_title_metadata WHERE media_id IN (\(placeholders))"
            if sqlite3_prepare_v2(handle, publicSQL, -1, &publicStatement, nil) == SQLITE_OK,
               let publicStatement {
                defer { sqlite3_finalize(publicStatement) }
                for (index, mediaID) in chunk.enumerated() {
                    bind(mediaID, at: Int32(index + 1), in: publicStatement)
                }
                while sqlite3_step(publicStatement) == SQLITE_ROW {
                    guard let mediaID = columnText(publicStatement, 0),
                          let payload = columnText(publicStatement, 1),
                          let data = payload.data(using: .utf8) else { continue }
                    result.publicTitles[mediaID, default: []].append(data)
                }
            }

            var attemptStatement: OpaquePointer?
            let attemptSQL = "SELECT media_id,provider,attempted_at FROM public_title_metadata_attempts WHERE lookup_version=? AND media_id IN (\(placeholders))"
            if sqlite3_prepare_v2(handle, attemptSQL, -1, &attemptStatement, nil) == SQLITE_OK,
               let attemptStatement {
                defer { sqlite3_finalize(attemptStatement) }
                sqlite3_bind_int(attemptStatement, 1, Int32(PublicTitleMetadataRefreshPolicy.lookupVersion))
                for (index, mediaID) in chunk.enumerated() {
                    bind(mediaID, at: Int32(index + 2), in: attemptStatement)
                }
                while sqlite3_step(attemptStatement) == SQLITE_ROW {
                    guard let mediaID = columnText(attemptStatement, 0),
                          let provider = columnText(attemptStatement, 1) else { continue }
                    result.publicAttempts[mediaID, default: [:]][provider] = Date(
                        timeIntervalSince1970: sqlite3_column_double(attemptStatement, 2)
                    )
                }
            }
        }
        return result
    }

    func saveReferenceMetadata(_ metadata: ReferenceTitleMetadata, mediaID: String) {
        guard let handle,
              let data = try? JSONEncoder().encode(metadata),
              let payload = String(data: data, encoding: .utf8) else { return }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO reference_metadata_cache(media_id,payload,fetched_at) VALUES(?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        bind(payload, at: 2, in: statement)
        sqlite3_bind_double(statement, 3, metadata.fetchedAt.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func loadCatalog() -> [MediaItem] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let sql = """
        SELECT m.id,m.api_id,m.title,m.subtitle,m.synopsis,m.year,m.kind,m.symbol,m.palette,m.artwork_url,m.source,
               i.imdb_id,i.genres,i.rating,i.votes
        FROM media m LEFT JOIN imdb_media_metadata i ON i.media_id=m.id
        ORDER BY m.updated_at DESC,m.title COLLATE NOCASE
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let source = columnText(statement, 10) ?? "api"
            let storedVotes = sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 14))
            result.append(MediaItem(
                id: columnText(statement, 0) ?? UUID().uuidString,
                apiID: columnText(statement, 1),
                title: columnText(statement, 2) ?? "Untitled",
                subtitle: columnText(statement, 3) ?? "",
                synopsis: columnText(statement, 4) ?? "",
                year: columnText(statement, 5) ?? "",
                kind: columnText(statement, 6) ?? "Movie",
                symbol: columnText(statement, 7) ?? "film",
                palette: Int(sqlite3_column_int(statement, 8)),
                artworkURL: columnText(statement, 9).flatMap { URL(string: $0) },
                isRemote: source == "api",
                imdbID: columnText(statement, 11),
                genres: Self.decodeGenres(columnText(statement, 12)),
                imdbRating: columnText(statement, 13),
                imdbVotes: storedVotes
            ))
        }
        return result
    }

    func loadDetailsPayload(for id: String) -> (payload: Data, fetchedAt: Date)? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        let sql = "SELECT payload,fetched_at FROM media_details_cache WHERE media_id=?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let payload = columnText(statement, 0) else { return nil }
        return (Data(payload.utf8), Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)))
    }

    func saveDetailsPayload(_ payload: Data, for id: String, fetchedAt: Date) {
        guard let handle, let json = String(data: payload, encoding: .utf8) else { return }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO media_details_cache(media_id,payload,fetched_at) VALUES(?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        bind(json, at: 2, in: statement)
        sqlite3_bind_double(statement, 3, fetchedAt.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func saveIMDbMetadata(_ metadata: IMDbTitleMetadata, for mediaID: String) {
        saveIMDbMetadata([mediaID: metadata])
    }

    func saveIMDbMetadata(_ metadataByMediaID: [String: IMDbTitleMetadata]) {
        guard let handle, !metadataByMediaID.isEmpty,
              sqlite3_exec(handle, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { return }
        var committed = false
        defer { if !committed { _ = sqlite3_exec(handle, "ROLLBACK;", nil, nil, nil) } }
        let sql = "INSERT OR REPLACE INTO imdb_media_metadata(media_id,imdb_id,genres,rating,votes) VALUES(?,?,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        for (mediaID, metadata) in metadataByMediaID {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(mediaID, at: 1, in: statement)
            bind(metadata.tconst, at: 2, in: statement)
            bind(Self.encodeGenres(metadata.genres), at: 3, in: statement)
            if let rating = metadata.rating { bind(String(format: "%.1f", rating), at: 4, in: statement) }
            else { sqlite3_bind_null(statement, 4) }
            if let votes = metadata.votes { sqlite3_bind_int(statement, 5, Int32(votes)) }
            else { sqlite3_bind_null(statement, 5) }
            guard sqlite3_step(statement) == SQLITE_DONE else { return }
        }
        committed = sqlite3_exec(handle, "COMMIT;", nil, nil, nil) == SQLITE_OK
    }

    func cachedIMDbArtwork(for tconst: String) -> (cached: Bool, data: Data?) {
        guard let handle else { return (false, nil) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT image_data FROM imdb_artwork_cache WHERE tconst=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return (false, nil) }
        defer { sqlite3_finalize(statement) }
        bind(tconst, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return (false, nil) }
        let length = Int(sqlite3_column_bytes(statement, 0))
        guard length > 0, let bytes = sqlite3_column_blob(statement, 0) else { return (true, nil) }
        return (true, Data(bytes: bytes, count: length))
    }

    func saveIMDbArtwork(_ data: Data?, sourceURL: String?, for tconst: String) {
        guard let handle else { return }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO imdb_artwork_cache(tconst,image_data,source_url,cached_at) VALUES(?,?,?,?)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(tconst, at: 1, in: statement)
        if let data, !data.isEmpty {
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
            }
        } else {
            sqlite3_bind_null(statement, 2)
        }
        bind(sourceURL, at: 3, in: statement)
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func loadSavedIDs() -> Set<String> {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT media_id FROM saved_items", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = columnText(statement, 0) { result.insert(id) }
        }
        return result
    }

    func loadPersonalRatings() -> [String: PersonalRating] {
        guard let handle else { return [:] }
        var statement: OpaquePointer?
        let sql = "SELECT media_id,rating,item_payload,updated_at FROM personal_ratings"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }
        var result: [String: PersonalRating] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let mediaID = columnText(statement, 0),
                  let payload = columnText(statement, 2),
                  let data = payload.data(using: .utf8),
                  let item = try? JSONDecoder().decode(MediaItem.self, from: data) else { continue }
            result[mediaID] = PersonalRating(
                rating: Int(sqlite3_column_int(statement, 1)),
                item: item,
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            )
        }
        return result
    }

    func setPersonalRating(_ rating: Int?, for item: MediaItem) -> Bool {
        guard let handle else { return false }
        var statement: OpaquePointer?
        if let rating {
            guard (1...5).contains(rating),
                  let data = try? JSONEncoder().encode(item),
                  let payload = String(data: data, encoding: .utf8) else { return false }
            let sql = "INSERT OR REPLACE INTO personal_ratings(media_id,rating,item_payload,updated_at) VALUES(?,?,?,?)"
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
            bind(item.id, at: 1, in: statement)
            sqlite3_bind_int(statement, 2, Int32(rating))
            bind(payload, at: 3, in: statement)
            sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        } else {
            guard sqlite3_prepare_v2(handle, "DELETE FROM personal_ratings WHERE media_id=?", -1, &statement, nil) == SQLITE_OK,
                  let statement else { return false }
            bind(item.id, at: 1, in: statement)
            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
    }

    func updatePersonalRatingSnapshot(_ item: MediaItem) -> Bool {
        guard let handle,
              let data = try? JSONEncoder().encode(item),
              let payload = String(data: data, encoding: .utf8) else { return false }
        var statement: OpaquePointer?
        let sql = "UPDATE personal_ratings SET item_payload=? WHERE media_id=?"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(payload, at: 1, in: statement)
        bind(item.id, at: 2, in: statement)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    func loadDownloadedMedia() -> [DownloadedMedia] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let sql = "SELECT id,title,file_path,byte_count,segment_count,created_at,catalog_media_id,episode_id,source_title FROM downloaded_media ORDER BY created_at DESC"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [DownloadedMedia] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = columnText(statement, 2) else { continue }
            let fileURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            result.append(DownloadedMedia(
                id: columnText(statement, 0) ?? UUID().uuidString,
                title: columnText(statement, 1) ?? fileURL.deletingPathExtension().lastPathComponent,
                sourceTitle: columnText(statement, 8) ?? "",
                fileURL: fileURL,
                byteCount: sqlite3_column_int64(statement, 3),
                segmentCount: Int(sqlite3_column_int(statement, 4)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                catalogMediaID: columnText(statement, 6),
                episodeID: columnText(statement, 7)
            ))
        }
        return result
    }

    func saveDownloadedMedia(_ item: DownloadedMedia) {
        guard let handle else { return }
        let sql = "INSERT OR REPLACE INTO downloaded_media(id,title,source_title,file_path,byte_count,segment_count,created_at,catalog_media_id,episode_id) VALUES(?,?,?,?,?,?,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(item.id, at: 1, in: statement)
        bind(item.title, at: 2, in: statement)
        bind(item.sourceTitle, at: 3, in: statement)
        bind(item.fileURL.path, at: 4, in: statement)
        sqlite3_bind_int64(statement, 5, item.byteCount)
        sqlite3_bind_int(statement, 6, Int32(item.segmentCount))
        sqlite3_bind_double(statement, 7, item.createdAt.timeIntervalSince1970)
        bind(item.catalogMediaID, at: 8, in: statement)
        bind(item.episodeID, at: 9, in: statement)
        sqlite3_step(statement)
    }

    func removeDownloadedMedia(_ id: String) {
        guard let handle else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM downloaded_media WHERE id=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        sqlite3_step(statement)
    }

    func replaceRemoteCatalog(_ items: [MediaItem]) {
        guard execute("BEGIN IMMEDIATE;") == SQLITE_OK else { return }
        guard execute("DELETE FROM media WHERE source='api';") == SQLITE_OK else {
            execute("ROLLBACK;")
            return
        }
        guard save(items, source: "api") else {
            execute("ROLLBACK;")
            return
        }
        if execute("COMMIT;") != SQLITE_OK { execute("ROLLBACK;") }
    }

    func saveRemoteItems(_ items: [MediaItem]) {
        _ = save(items, source: "api")
    }

    func saveLocalItems(_ items: [MediaItem]) {
        _ = save(items, source: "local")
    }

    func setSaved(_ id: String, saved: Bool) {
        guard let handle else { return }
        let sql = saved
            ? "INSERT OR IGNORE INTO saved_items(media_id,saved_at) VALUES(?,strftime('%s','now'))"
            : "DELETE FROM saved_items WHERE media_id=?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        sqlite3_step(statement)
    }

    private func save(_ items: [MediaItem], source: String) -> Bool {
        guard let handle else { return false }
        let sql = "INSERT OR REPLACE INTO media(id,api_id,title,subtitle,synopsis,year,kind,symbol,palette,artwork_url,source,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,strftime('%s','now'))"
        var success = true
        for item in items {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                success = false
                continue
            }
            bind(item.id, at: 1, in: statement)
            bind(item.apiID, at: 2, in: statement)
            bind(item.title, at: 3, in: statement)
            bind(item.subtitle, at: 4, in: statement)
            bind(item.synopsis, at: 5, in: statement)
            bind(item.year, at: 6, in: statement)
            bind(item.kind, at: 7, in: statement)
            bind(item.symbol, at: 8, in: statement)
            sqlite3_bind_int(statement, 9, Int32(item.palette))
            bind(item.artworkURL?.absoluteString, at: 10, in: statement)
            bind(source, at: 11, in: statement)
            if sqlite3_step(statement) != SQLITE_DONE { success = false }
            sqlite3_finalize(statement)
        }
        return success
    }

    @discardableResult
    private func execute(_ sql: String) -> Int32 {
        guard let handle else { return SQLITE_MISUSE }
        return sqlite3_exec(handle, sql, nil, nil, nil)
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer) {
        guard let value else { sqlite3_bind_null(statement, index); return }
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        guard let handle else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, 1) == column { return true }
        }
        return false
    }
}

extension MediaDatabase {
    func watchProgress(
        mediaID: String,
        episodeID: String?,
        episodeLabel: String?,
        episodeTitle: String?
    ) -> WatchProgress? {
        if let exact = watchProgress(mediaID: mediaID, episodeID: episodeID) { return exact }
        let requestedLabel = episodeLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedTitle = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let handle else { return nil }
        guard requestedLabel?.isEmpty == false || requestedTitle?.isEmpty == false else { return nil }

        let sql = """
        SELECT media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
               position_seconds,duration_seconds,watched_seconds,is_watched,updated_at
        FROM watch_progress WHERE media_id=? ORDER BY updated_at DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)

        var rows: [WatchProgress] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let row = Self.readWatchProgress(statement) { rows.append(row) }
        }

        if let requestedLabel, !requestedLabel.isEmpty {
            let target = Self.normalizedEpisodeIdentity(requestedLabel)
            if !target.isEmpty {
                let matches = rows.filter {
                    guard let label = $0.episodeLabel else { return false }
                    return Self.normalizedEpisodeIdentity(label) == target
                }
                if matches.count == 1 { return matches[0] }
                if !matches.isEmpty { return nil }
            }
        }

        guard let requestedTitle, !requestedTitle.isEmpty else { return nil }
        let matches = rows.filter { row in
            guard let title = row.episodeTitle,
                  title.localizedCaseInsensitiveCompare(requestedTitle) == .orderedSame else { return false }
            if requestedLabel?.isEmpty == false {
                return row.episodeLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            }
            return true
        }
        return matches.count == 1 ? matches[0] : nil
    }

    func watchProgress(mediaID: String, episodeID: String?) -> WatchProgress? {
        guard let handle else { return nil }
        let sql = """
        SELECT media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
               position_seconds,duration_seconds,watched_seconds,is_watched,updated_at
        FROM watch_progress WHERE media_id=? AND episode_id=? LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(mediaID, at: 1, in: statement)
        bind(episodeID ?? "", at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Self.readWatchProgress(statement)
    }

    func loadWatchedIMDbIDs() -> Set<String> {
        guard let handle else { return [] }
        let sql = """
        SELECT DISTINCT imdb_id
        FROM watch_progress
        WHERE imdb_id IS NOT NULL AND trim(imdb_id)<>''
          AND (is_watched=1 OR
               (duration_seconds>0 AND position_seconds>=duration_seconds*0.9))
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let imdbID = columnText(statement, 0) { result.insert(imdbID) }
        }
        return result
    }

    func loadWatchProgress(limit: Int? = 500, includeWatched: Bool = false) -> [WatchProgress] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let predicate = includeWatched ? "" : "WHERE is_watched=0"
        let sql = """
        SELECT media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
               position_seconds,duration_seconds,watched_seconds,is_watched,updated_at
        FROM watch_progress \(predicate)
        ORDER BY updated_at DESC LIMIT ?
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, limit.map { Int32(max(1, min($0, 2_000))) } ?? -1)
        var result: [WatchProgress] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let row = Self.readWatchProgress(statement) { result.append(row) }
        }
        return result
    }

    @discardableResult
    func beginWatchSession(progress: WatchProgress, playerKind: String) -> String? {
        guard let handle else { return nil }
        let id = UUID().uuidString
        let sql = """
        INSERT INTO watch_sessions(id,media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
                                   started_at,position_seconds,duration_seconds,watched_seconds,player_kind,ended_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,NULL)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        Self.bind(progress, to: statement, startingAt: 2, using: self)
        sqlite3_bind_double(statement, 12, Date().timeIntervalSince1970)
        sqlite3_bind_double(statement, 13, progress.positionSeconds)
        if let duration = progress.durationSeconds { sqlite3_bind_double(statement, 14, duration) }
        else { sqlite3_bind_null(statement, 14) }
        bind(playerKind, at: 15, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
        saveWatchProgress(progress)
        return id
    }

    func updateWatchSession(id: String, progress: WatchProgress, watchedDelta: Double, endedAt: Date? = nil) {
        guard let handle else { return }
        saveWatchProgress(progress)
        let sql = endedAt == nil
            ? "UPDATE watch_sessions SET position_seconds=?,duration_seconds=?,watched_seconds=watched_seconds+? WHERE id=?"
            : "UPDATE watch_sessions SET position_seconds=?,duration_seconds=?,watched_seconds=watched_seconds+?,ended_at=? WHERE id=?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, max(0, progress.positionSeconds))
        if let duration = progress.durationSeconds, duration.isFinite { sqlite3_bind_double(statement, 2, max(0, duration)) }
        else { sqlite3_bind_null(statement, 2) }
        sqlite3_bind_double(statement, 3, max(0, min(60, watchedDelta)))
        if let endedAt {
            sqlite3_bind_double(statement, 4, endedAt.timeIntervalSince1970)
            bind(id, at: 5, in: statement)
        } else {
            bind(id, at: 4, in: statement)
        }
        sqlite3_step(statement)
    }

    func setWatched(_ progress: WatchProgress, watched: Bool) {
        var updated = progress
        updated.isWatched = watched
        if watched {
            if let duration = updated.durationSeconds, duration.isFinite, duration > 0 {
                updated.positionSeconds = duration
            }
        } else {
            updated.positionSeconds = 0
        }
        updated.updatedAt = Date()
        saveWatchProgress(updated)
    }

    func loadWatchHistory(limit: Int? = 500) -> [WatchHistoryEntry] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let sql = """
        SELECT id,media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
               started_at,position_seconds,duration_seconds,watched_seconds,player_kind
        FROM watch_sessions WHERE watched_seconds>0 ORDER BY started_at DESC LIMIT ?
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, limit.map { Int32(max(1, min($0, 2_000))) } ?? -1)
        var result: [WatchHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = columnText(statement, 0), let mediaID = columnText(statement, 1) else { continue }
            result.append(WatchHistoryEntry(
                id: id,
                mediaID: mediaID,
                episodeID: (columnText(statement, 2) ?? "").nilIfEmpty,
                mediaTitle: columnText(statement, 3) ?? "Untitled",
                kind: columnText(statement, 4) ?? "Movie",
                episodeTitle: columnText(statement, 5),
                episodeLabel: columnText(statement, 6),
                year: columnText(statement, 7) ?? "",
                artworkURL: columnText(statement, 8).flatMap(URL.init(string:)),
                imdbID: columnText(statement, 9),
                genres: Self.decodeGenres(columnText(statement, 10)),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
                positionSeconds: sqlite3_column_double(statement, 12),
                durationSeconds: Self.optionalDouble(statement, 13),
                watchedSeconds: sqlite3_column_double(statement, 14),
                playerKind: columnText(statement, 15) ?? "AVPlayer"
            ))
        }
        return result
    }

    func mergeViewingData(_ export: ViewingDataExport) -> Bool {
        guard let export = try? export.validated(), handle != nil,
              execute("BEGIN IMMEDIATE") == SQLITE_OK else { return false }

        for progress in export.progress where !mergeWatchProgress(progress) {
            _ = execute("ROLLBACK")
            return false
        }
        for entry in export.history where !mergeWatchHistory(entry) {
            _ = execute("ROLLBACK")
            return false
        }
        for rating in export.personalRatings where !mergePersonalRating(rating) {
            _ = execute("ROLLBACK")
            return false
        }

        guard execute("COMMIT") == SQLITE_OK else {
            _ = execute("ROLLBACK")
            return false
        }
        return true
    }

    func clearViewingActivity() -> Bool {
        guard execute("BEGIN IMMEDIATE") == SQLITE_OK else { return false }
        guard execute("DELETE FROM watch_sessions") == SQLITE_OK,
              execute("DELETE FROM watch_progress") == SQLITE_OK else {
            _ = execute("ROLLBACK")
            return false
        }
        guard execute("COMMIT") == SQLITE_OK else {
            _ = execute("ROLLBACK")
            return false
        }
        return true
    }

    func viewingStats() -> ViewingStats {
        guard let handle else { return ViewingStats() }
        return Self.viewingStats(handle: handle)
    }

    func viewingStatsAsync() async -> ViewingStats {
        let path = databasePath
        return await Task.detached(priority: .utility) {
            var readHandle: OpaquePointer?
            guard sqlite3_open_v2(path, &readHandle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
                  let readHandle else { return ViewingStats() }
            defer { sqlite3_close(readHandle) }
            return Self.viewingStats(handle: readHandle)
        }.value
    }

    private static func viewingStats(handle: OpaquePointer) -> ViewingStats {
        var stats = ViewingStats()
        var sessionStatement: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT genres,watched_seconds FROM watch_sessions WHERE watched_seconds>0", -1, &sessionStatement, nil) == SQLITE_OK,
           let sessionStatement {
            while sqlite3_step(sessionStatement) == SQLITE_ROW {
                let watchedSeconds = sqlite3_column_double(sessionStatement, 1)
                stats.totalWatchedSeconds += watchedSeconds
                stats.sessionCount += 1
                let genreData = sqlite3_column_text(sessionStatement, 0).map { String(cString: $0) }
                for genre in Self.decodeGenres(genreData) {
                    stats.genreSeconds[genre, default: 0] += watchedSeconds
                }
            }
            sqlite3_finalize(sessionStatement)
        }
        stats.completedMovies = scalarCount("SELECT COUNT(*) FROM watch_progress WHERE is_watched=1 AND kind='Movie'", handle: handle)
        stats.completedEpisodes = scalarCount("SELECT COUNT(*) FROM watch_progress WHERE is_watched=1 AND kind='Series' AND episode_id<>''", handle: handle)
        return stats
    }

    func loadGenrePreferences(category: String) -> Set<String> {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT genre FROM genre_preferences WHERE category=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(category, at: 1, in: statement)
        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let genre = columnText(statement, 0) { result.insert(genre) }
        }
        return result
    }

    func saveGenrePreferences(_ genres: Set<String>, category: String) {
        guard let handle else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM genre_preferences WHERE category=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return }
        bind(category, at: 1, in: statement)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
        for genre in genres {
            var insert: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT OR IGNORE INTO genre_preferences(category,genre) VALUES(?,?)", -1, &insert, nil) == SQLITE_OK,
                  let insert else { continue }
            bind(category, at: 1, in: insert)
            bind(genre, at: 2, in: insert)
            sqlite3_step(insert)
            sqlite3_finalize(insert)
        }
    }

    private func saveWatchProgress(_ progress: WatchProgress) {
        guard let handle else { return }
        let sql = """
        INSERT INTO watch_progress(media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
                                   position_seconds,duration_seconds,watched_seconds,is_watched,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(media_id,episode_id) DO UPDATE SET media_title=excluded.media_title,kind=excluded.kind,
          episode_title=excluded.episode_title,episode_label=excluded.episode_label,year=excluded.year,
          artwork_url=excluded.artwork_url,imdb_id=excluded.imdb_id,genres=excluded.genres,
          position_seconds=excluded.position_seconds,duration_seconds=COALESCE(excluded.duration_seconds,watch_progress.duration_seconds),
          watched_seconds=excluded.watched_seconds,is_watched=excluded.is_watched,updated_at=excluded.updated_at
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        Self.bind(progress, to: statement, startingAt: 1, using: self)
        sqlite3_bind_double(statement, 11, max(0, progress.positionSeconds))
        if let duration = progress.durationSeconds, duration.isFinite { sqlite3_bind_double(statement, 12, max(0, duration)) }
        else { sqlite3_bind_null(statement, 12) }
        sqlite3_bind_double(statement, 13, max(0, progress.watchedSeconds))
        sqlite3_bind_int(statement, 14, progress.isWatched ? 1 : 0)
        sqlite3_bind_double(statement, 15, progress.updatedAt.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func mergeWatchProgress(_ progress: WatchProgress) -> Bool {
        guard let handle else { return false }
        let sql = """
        INSERT INTO watch_progress(media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
                                   position_seconds,duration_seconds,watched_seconds,is_watched,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(media_id,episode_id) DO UPDATE SET media_title=excluded.media_title,kind=excluded.kind,
          episode_title=excluded.episode_title,episode_label=excluded.episode_label,year=excluded.year,
          artwork_url=excluded.artwork_url,imdb_id=excluded.imdb_id,genres=excluded.genres,
          position_seconds=excluded.position_seconds,duration_seconds=COALESCE(excluded.duration_seconds,watch_progress.duration_seconds),
          watched_seconds=excluded.watched_seconds,is_watched=excluded.is_watched,updated_at=excluded.updated_at
        WHERE excluded.updated_at>watch_progress.updated_at
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        Self.bind(progress, to: statement, startingAt: 1, using: self)
        sqlite3_bind_double(statement, 11, progress.positionSeconds)
        if let duration = progress.durationSeconds { sqlite3_bind_double(statement, 12, duration) }
        else { sqlite3_bind_null(statement, 12) }
        sqlite3_bind_double(statement, 13, progress.watchedSeconds)
        sqlite3_bind_int(statement, 14, progress.isWatched ? 1 : 0)
        sqlite3_bind_double(statement, 15, progress.updatedAt.timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func mergeWatchHistory(_ entry: WatchHistoryEntry) -> Bool {
        guard let handle else { return false }
        let sql = """
        INSERT OR IGNORE INTO watch_sessions(id,media_id,episode_id,media_title,kind,episode_title,episode_label,year,artwork_url,imdb_id,genres,
                                             started_at,position_seconds,duration_seconds,watched_seconds,player_kind,ended_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(entry.id, at: 1, in: statement)
        bind(entry.mediaID, at: 2, in: statement)
        bind(entry.episodeID ?? "", at: 3, in: statement)
        bind(entry.mediaTitle, at: 4, in: statement)
        bind(entry.kind, at: 5, in: statement)
        bind(entry.episodeTitle, at: 6, in: statement)
        bind(entry.episodeLabel, at: 7, in: statement)
        bind(entry.year, at: 8, in: statement)
        bind(entry.artworkURL?.absoluteString, at: 9, in: statement)
        bind(entry.imdbID, at: 10, in: statement)
        bind(Self.encodeGenres(entry.genres), at: 11, in: statement)
        sqlite3_bind_double(statement, 12, entry.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 13, entry.positionSeconds)
        if let duration = entry.durationSeconds { sqlite3_bind_double(statement, 14, duration) }
        else { sqlite3_bind_null(statement, 14) }
        sqlite3_bind_double(statement, 15, entry.watchedSeconds)
        bind(entry.playerKind, at: 16, in: statement)
        sqlite3_bind_double(statement, 17, entry.startedAt.timeIntervalSince1970 + entry.watchedSeconds)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func mergePersonalRating(_ rating: PersonalRating) -> Bool {
        guard let handle,
              let data = try? JSONEncoder().encode(rating.item),
              let payload = String(data: data, encoding: .utf8) else { return false }
        let sql = """
        INSERT INTO personal_ratings(media_id,rating,item_payload,updated_at) VALUES(?,?,?,?)
        ON CONFLICT(media_id) DO UPDATE SET rating=excluded.rating,item_payload=excluded.item_payload,updated_at=excluded.updated_at
        WHERE excluded.updated_at>personal_ratings.updated_at
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(rating.item.id, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(rating.rating))
        bind(payload, at: 3, in: statement)
        sqlite3_bind_double(statement, 4, rating.updatedAt.timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    func closeUnfinishedWatchSessions() {
        guard let handle else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle,
            "UPDATE watch_sessions SET ended_at=? WHERE ended_at IS NULL",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private static func readWatchProgress(_ statement: OpaquePointer) -> WatchProgress? {
        guard let mediaID = sqlite3_column_text(statement, 0).map({ String(cString: $0) }) else { return nil }
        return WatchProgress(
            mediaID: mediaID,
            episodeID: (sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "").nilIfEmpty,
            mediaTitle: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "Untitled",
            kind: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "Movie",
            episodeTitle: sqlite3_column_text(statement, 4).map { String(cString: $0) },
            episodeLabel: sqlite3_column_text(statement, 5).map { String(cString: $0) },
            year: sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "",
            artworkURL: sqlite3_column_text(statement, 7).map { URL(string: String(cString: $0)) }.flatMap { $0 },
            imdbID: sqlite3_column_text(statement, 8).map { String(cString: $0) },
            genres: decodeGenres(sqlite3_column_text(statement, 9).map { String(cString: $0) }),
            positionSeconds: sqlite3_column_double(statement, 10),
            durationSeconds: optionalDouble(statement, 11),
            watchedSeconds: sqlite3_column_double(statement, 12),
            isWatched: sqlite3_column_int(statement, 13) != 0,
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 14))
        )
    }

    private static func normalizedEpisodeIdentity(_ value: String) -> String {
        let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if numbers.count == 2 { return "s\(numbers[0])e\(numbers[1])" }
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func bind(_ progress: WatchProgress, to statement: OpaquePointer, startingAt index: Int32, using database: MediaDatabase) {
        database.bind(progress.mediaID, at: index, in: statement)
        database.bind(progress.episodeID ?? "", at: index + 1, in: statement)
        database.bind(progress.mediaTitle, at: index + 2, in: statement)
        database.bind(progress.kind, at: index + 3, in: statement)
        database.bind(progress.episodeTitle, at: index + 4, in: statement)
        database.bind(progress.episodeLabel, at: index + 5, in: statement)
        database.bind(progress.year, at: index + 6, in: statement)
        database.bind(progress.artworkURL?.absoluteString, at: index + 7, in: statement)
        database.bind(progress.imdbID, at: index + 8, in: statement)
        database.bind(encodeGenres(progress.genres), at: index + 9, in: statement)
    }

    private static func encodeGenres(_ genres: [String]) -> String {
        guard let data = try? JSONEncoder().encode(genres), let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }

    private static func decodeGenres(_ value: String?) -> [String] {
        guard let value, let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func optionalDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_double(statement, index)
        return value.isFinite ? value : nil
    }

    private static func scalarCount(_ sql: String, handle: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }
}

enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case completed = "Downloaded"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

private struct SeasonDownloadSummary {
    var queued = 0
    var unavailable = 0
    var alreadyQueuedOrDownloaded = 0
}

@MainActor
final class DownloadEntry: ObservableObject, Identifiable {
    let id: String
    let title: String
    let sourceTitle: String
    let createdAt: Date
    let catalogMediaID: String?
    let episodeID: String?
    private(set) var source: MediaStreamSource?
    @Published var status: DownloadStatus
    @Published var progress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64?
    @Published var completedSegments = 0
    @Published var totalSegments: Int?
    @Published var fileURL: URL?
    @Published var errorMessage: String?
    fileprivate var task: Task<Void, Never>?

    init(title: String, source: MediaStreamSource, catalogMediaID: String?, episodeID: String?) {
        id = UUID().uuidString
        self.title = title
        sourceTitle = source.title
        self.source = source
        self.catalogMediaID = catalogMediaID
        self.episodeID = episodeID
        createdAt = Date()
        status = .queued
    }

    init(completed item: DownloadedMedia) {
        id = item.id
        title = item.title
        sourceTitle = item.sourceTitle
        createdAt = item.createdAt
        catalogMediaID = item.catalogMediaID
        episodeID = item.episodeID
        status = .completed
        progress = 1
        downloadedBytes = item.byteCount
        totalBytes = item.byteCount
        completedSegments = item.segmentCount
        totalSegments = item.segmentCount
        fileURL = item.fileURL
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    private struct CompletedDownloadKey: Hashable {
        let mediaItemID: String
        let episodeID: String?
    }

    private struct CompletedDownloadRecord {
        let fileURL: URL
        let catalogMediaID: String?
        let episodeID: String?
    }

    @Published private(set) var entries: [DownloadEntry]
    @Published private(set) var offlineRevision = 0
    private let database: MediaDatabase
    private var completedByIdentity: [CompletedDownloadKey: CompletedDownloadRecord] = [:]
    private var completedByTitle: [String: [CompletedDownloadRecord]] = [:]
    private var activeCount = 0
    private let maximumActiveDownloads = 2

    init(database: MediaDatabase) {
        self.database = database
        entries = database.loadDownloadedMedia().map(DownloadEntry.init(completed:))
        rebuildCompletedDownloadsIndex()
    }

    @discardableResult
    func enqueue(source: MediaStreamSource, title: String, catalogMediaID: String? = nil, episodeID: String? = nil) -> Bool {
        if entries.contains(where: {
            let sameMediaQuality = catalogMediaID != nil
                && $0.catalogMediaID == catalogMediaID
                && $0.episodeID == episodeID
                && $0.sourceTitle.localizedCaseInsensitiveCompare(source.title) == .orderedSame
            let activeDuplicate = $0.source?.url == source.url
                && ($0.status == .queued || $0.status == .downloading)
            return activeDuplicate || (sameMediaQuality
                && ($0.status == .queued || $0.status == .downloading || $0.status == .completed))
        }) {
            return false
        }
        let entry = DownloadEntry(title: title, source: source, catalogMediaID: catalogMediaID, episodeID: episodeID)
        entries.insert(entry, at: 0)
        startNext()
        return true
    }

    fileprivate func enqueueSeason(
        _ season: MediaSeason,
        series: MediaItem,
        preferredQuality: String? = nil
    ) -> SeasonDownloadSummary {
        var summary = SeasonDownloadSummary()
        for episode in season.episodes {
            var seen = Set<String>()
            let sources = (episode.downloadSources + episode.sources).filter {
                seen.insert($0.url.absoluteString).inserted
            }.filter { !["m3u8", "mpd"].contains($0.url.pathExtension.lowercased()) }
            guard let source = MediaStreamSourceSelection.preferred(in: sources, selectedTitle: preferredQuality) else {
                summary.unavailable += 1
                continue
            }
            let title = "\(series.title) · \(episode.episodeLabel) · \(episode.title)"
            if enqueue(source: source, title: title, catalogMediaID: series.id, episodeID: episode.id) {
                summary.queued += 1
            } else {
                summary.alreadyQueuedOrDownloaded += 1
            }
        }
        return summary
    }

    func completedDownload(mediaItemID: String, episodeID: String?, title: String) -> URL? {
        let identity = CompletedDownloadKey(mediaItemID: mediaItemID, episodeID: episodeID)
        if let exact = completedByIdentity[identity],
           FileManager.default.fileExists(atPath: exact.fileURL.path) {
            return exact.fileURL
        }

        // Some catalog backends regenerate episode IDs. Preserve the offline match
        // when the same catalog item and episode title still identify the download.
        let titleKey = Self.normalizedDownloadTitle(title)
        for record in completedByTitle[titleKey] ?? [] {
            let matchesCatalog = record.catalogMediaID == mediaItemID
                || (record.catalogMediaID == nil && record.episodeID == nil)
            guard matchesCatalog, FileManager.default.fileExists(atPath: record.fileURL.path) else { continue }
            return record.fileURL
        }
        return nil
    }

    func cancel(_ entry: DownloadEntry) {
        guard entry.status == .queued || entry.status == .downloading else { return }
        entry.status = .cancelled
        entry.task?.cancel()
    }

    func retry(_ entry: DownloadEntry) {
        guard entry.status == .failed || entry.status == .cancelled,
              entry.source != nil,
              entry.task == nil else { return }
        entry.status = .queued
        entry.errorMessage = nil
        entry.progress = 0
        entry.downloadedBytes = 0
        entry.totalBytes = nil
        entry.completedSegments = 0
        entry.totalSegments = nil
        startNext()
    }

    func remove(_ entry: DownloadEntry) {
        guard entry.status != .downloading && entry.status != .queued else { return }
        if entry.status == .completed { database.removeDownloadedMedia(entry.id) }
        entries.removeAll { $0.id == entry.id }
        rebuildCompletedDownloadsIndex()
    }

    private func startNext() {
        while activeCount < maximumActiveDownloads,
              let entry = entries.first(where: { $0.status == .queued }),
              let source = entry.source {
            activeCount += 1
            entry.status = .downloading
            entry.task = Task { [weak self, weak entry] in
                guard let self, let entry else { return }
                await self.perform(entry, source: source)
            }
        }
    }

    private func perform(_ entry: DownloadEntry, source: MediaStreamSource) async {
        do {
            let fileExtension = source.url.pathExtension.lowercased()
            if ["m3u8", "mpd"].contains(fileExtension) {
                throw SegmentedDownloadError.unsupportedAdaptiveStream
            }
            let destination = try destinationURL(title: entry.title, source: source)
            entry.errorMessage = nil
            let report = try await SegmentedDownloader.download(
                source: DownloadRequestSource(url: source.url, headers: source.headers),
                to: destination
            ) { [weak self] completed, total, completedSegments, totalSegments in
                Task { @MainActor [weak self] in
                    self?.updateProgress(
                        id: entry.id,
                        completed: completed,
                        total: total,
                        completedSegments: completedSegments,
                        totalSegments: totalSegments
                    )
                }
            }
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                throw CancellationError()
            }
            entry.status = .completed
            entry.progress = 1
            entry.downloadedBytes = report.byteCount
            entry.totalBytes = report.byteCount
            entry.completedSegments = report.segmentCount
            entry.totalSegments = report.segmentCount
            entry.fileURL = destination
            let saved = DownloadedMedia(
                id: entry.id,
                title: entry.title,
                sourceTitle: source.title,
                fileURL: destination,
                byteCount: report.byteCount,
                segmentCount: report.segmentCount,
                createdAt: entry.createdAt,
                catalogMediaID: entry.catalogMediaID,
                episodeID: entry.episodeID
            )
            database.saveDownloadedMedia(saved)
            rebuildCompletedDownloadsIndex()
            offlineRevision += 1
        } catch is CancellationError {
            entry.status = .cancelled
            entry.errorMessage = nil
        } catch {
            entry.status = .failed
            entry.errorMessage = error.localizedDescription
        }
        entry.task = nil
        activeCount = max(0, activeCount - 1)
        startNext()
    }

    private func updateProgress(
        id: String,
        completed: Int64,
        total: Int64?,
        completedSegments: Int,
        totalSegments: Int?
    ) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        entry.downloadedBytes = completed
        entry.totalBytes = total
        entry.completedSegments = completedSegments
        entry.totalSegments = totalSegments
        if let total, total > 0 { entry.progress = min(1, Double(completed) / Double(total)) }
    }

    private func rebuildCompletedDownloadsIndex() {
        var byIdentity: [CompletedDownloadKey: CompletedDownloadRecord] = [:]
        var byTitle: [String: [CompletedDownloadRecord]] = [:]
        for entry in entries {
            guard entry.status == .completed, let fileURL = entry.fileURL else { continue }
            let record = CompletedDownloadRecord(
                fileURL: fileURL,
                catalogMediaID: entry.catalogMediaID,
                episodeID: entry.episodeID
            )
            if let mediaID = entry.catalogMediaID {
                let key = CompletedDownloadKey(mediaItemID: mediaID, episodeID: entry.episodeID)
                if byIdentity[key] == nil { byIdentity[key] = record }
            }
            byTitle[Self.normalizedDownloadTitle(entry.title), default: []].append(record)
        }
        completedByIdentity = byIdentity
        completedByTitle = byTitle
    }

    private static func normalizedDownloadTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func destinationURL(title: String, source: MediaStreamSource) throws -> URL {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw SegmentedDownloadError.invalidURL
        }
        let directory = downloads.appendingPathComponent("Denbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeTitle = title
            .replacingOccurrences(of: "[/\\\\:*?\"<>|\\r\\n]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = source.title.lowercased().hasPrefix("source ") ? "" : " - \(source.title)"
        let baseName = String("\(safeTitle.isEmpty ? "Video" : safeTitle)\(label)".prefix(120))
        let allowedExtensions: Set<String> = ["mp4", "m4v", "mkv", "mov", "webm", "avi", "ts", "mpeg", "mpg"]
        let ext = allowedExtensions.contains(source.url.pathExtension.lowercased()) ? source.url.pathExtension.lowercased() : "mp4"
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) (\(suffix)).\(ext)")
            suffix += 1
        }
        return candidate
    }
}

extension MediaItem {
    static let samples: [MediaItem] = [
        .init(id: "sample-1", title: "The Last Light", subtitle: "A story beyond the horizon", synopsis: "At the edge of a quiet coastal town, an unexpected discovery gives one family a reason to begin again.", year: "2025", kind: "Movie", symbol: "sun.horizon.fill", palette: 0),
        .init(id: "sample-2", title: "Blue District", subtitle: "Every street keeps a secret", synopsis: "A young architect returns home and finds that the city she remembers has changed in more ways than one.", year: "2024", kind: "Series", symbol: "building.2.fill", palette: 1),
        .init(id: "sample-3", title: "Northbound", subtitle: "A journey through winter", synopsis: "Two strangers share a long train ride through the mountains and a story neither planned to tell.", year: "2025", kind: "Movie", symbol: "snowflake", palette: 2),
        .init(id: "sample-4", title: "Small Worlds", subtitle: "Big ideas, close to home", synopsis: "A warm, lightly comic series about neighbours learning to make room for each other.", year: "2023", kind: "Series", symbol: "sparkles", palette: 3),
        .init(id: "sample-5", title: "Between Two Suns", subtitle: "Some choices change everything", synopsis: "A photographer follows a fading road across a bright and unfamiliar landscape.", year: "2024", kind: "Movie", symbol: "sun.max.fill", palette: 4),
        .init(id: "sample-6", title: "The Archive", subtitle: "Nothing disappears completely", synopsis: "A small museum team uncovers the people and places hidden inside an old collection.", year: "2025", kind: "Series", symbol: "books.vertical.fill", palette: 5),
        .init(id: "sample-7", title: "Silver Current", subtitle: "Follow the water home", synopsis: "A marine biologist returns to the island where her family first learned to read the sea.", year: "2022", kind: "Movie", symbol: "water.waves", palette: 6),
        .init(id: "sample-8", title: "After the Rain", subtitle: "A new season begins", synopsis: "Three friends reopen a neighborhood cinema and rediscover what made it matter.", year: "2024", kind: "Series", symbol: "cloud.sun.fill", palette: 7)
    ]
}

struct MainWindow: View {
    @EnvironmentObject private var model: LibraryModel
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.openWindow) private var openWindow
    @State private var detailPath: [MediaItem] = []

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 225)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                }

            detailNavigationStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1020, minHeight: 700)
        .onChange(of: model.playerURL) { url in
            guard url != nil, !model.isPlayerWindowOpen else { return }
            model.isPlayerWindowOpen = true
            openWindow(id: "denbox-player")
        }
        .onChange(of: model.selectedItem) { item in
            guard let item else { return }
            detailPath.append(item)
            model.selectedItem = nil
        }
        .onChange(of: model.section) { _ in
            detailPath.removeAll()
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
    }

    private var detailNavigationStack: some View {
        NavigationStack(path: $detailPath) {
            mainContent
                .navigationDestination(for: MediaItem.self) { item in
                    MediaDetailPage(item: item)
                        .environmentObject(model)
                }
        }
        .background(Color.canvas)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 34) {
                    if model.section == .home && model.searchText.isEmpty, let featured = model.visibleItems.first {
                        HeroFeature(item: featured)
                    }
                    pageHeading
                    if [.home, .movies, .shows, .watchlist].contains(model.section), !model.genreFacets.isEmpty {
                        GenreFilterBar()
                    }
                    if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if model.isSearchingRemoteSearch && !model.visibleItems.isEmpty {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text(DenboxLanguage.localizedMessage("Searching the catalog…"))
                                    .font(.denbox(size: 11))
                                    .foregroundStyle(Color.secondaryText)
                            }
                        }
                        if model.visibleItems.isEmpty {
                            if model.isSearchingRemoteSearch {
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text(DenboxLanguage.localizedMessage("Searching the catalog…"))
                                        .font(.denbox(size: 12))
                                        .foregroundStyle(Color.secondaryText)
                                }
                                .frame(maxWidth: .infinity, minHeight: 150)
                                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
                            } else {
                                EmptyLibraryState(isWatchlist: false, isMyRatings: false)
                            }
                        } else {
                            MediaGrid(items: model.visibleItems)
                        }
                    } else if model.section == .forYou {
                        PersonalizedRecommendationsPage()
                    } else if model.section == .genres {
                        GenresPage()
                    } else if model.section == .continueWatching {
                        ContinueWatchingPage()
                    } else if model.section == .watchHistory {
                        WatchHistoryPage()
                    } else if model.section == .viewingStats {
                        ViewingStatsPage()
                    } else if model.section == .imdbPeople {
                        IMDbPeoplePage()
                    } else if model.section == .imdbFranchises {
                        IMDbFranchisesPage()
                    } else if model.section == .downloads {
                        DownloadsView()
                    } else if model.section == .imdbCharts {
                        IMDbChartsPage()
                    } else if model.section == .releaseCalendar {
                        ReleaseCalendarPage()
                    } else if model.visibleItems.isEmpty {
                        EmptyLibraryState(
                            isWatchlist: model.section == .watchlist,
                            isMyRatings: model.section == .myRatings
                        )
                    } else {
                        if model.section == .home && model.searchText.isEmpty {
                            MediaShelf(title: "Featured in your library", subtitle: "A closer look at what’s available", items: Array(model.visibleItems.prefix(4)), landscape: true)
                            MediaShelf(title: "Movies", subtitle: "Stories for tonight", items: model.visibleItems.filter { $0.kind == "Movie" })
                            MediaShelf(title: "TV Shows", subtitle: "A little more to look forward to", items: model.visibleItems.filter { $0.kind == "Series" })
                        } else {
                            MediaGrid(items: model.visibleItems)
                        }
                    }
                    if model.section != .downloads && model.section != .watchlist && model.section != .myRatings
                        && (model.canLoadMoreCatalog || model.isLoadingMore) {
                        CatalogPaginationFooter()
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 20)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Text(model.section.displayName)
                .font(.denbox(size: 21, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondaryText)
                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
                    .onChange(of: model.searchText) { newValue in
                        model.searchRemote(newValue)
                    }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.08), in: Capsule())
            Button { model.openLocalVideo() } label: {
                Label("Open Video", systemImage: "play.rectangle")
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.85))
            .help("Play a video file stored on this Mac")
            Button {
                Task { await model.refreshCatalog() }
            } label: {
                if model.isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.85))
            .disabled(model.isConnecting)
            .help("Refresh the movie and series catalog")
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 17)
        .background(Color.canvas.opacity(0.96))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    @ViewBuilder
    private var pageHeading: some View {
        if model.section != .home || !model.searchText.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.searchText.isEmpty ? model.section.displayName : "Search results")
                    .font(.denbox(size: 31, weight: .bold))
                Text(DenboxLanguage.localizedMessage(headingSubtitle))
                    .font(.denbox(size: 13))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.top, 12)
        }
    }

    private var headingSubtitle: String {
        if !model.searchText.isEmpty { return "\(model.visibleItems.count) results · From \(model.catalogName)" }
        return switch model.section {
        case .forYou: "Recommendations from IMDb, tuned to your viewing, ratings, and chosen genres"
        case .genres: "Choose your favorite genres and filter the local catalog"
        case .continueWatching: "\(model.continueWatchingItems.count) titles ready to resume"
        case .watchHistory: "\(model.watchHistory.count) recent sessions stored on this Mac"
        case .viewingStats: "Your viewing time, completed titles, and favorite genres"
        case .imdbCharts: "Top rated titles, most-voted lists, and live box office"
        case .releaseCalendar: "Persian calendar of movie releases and TV episode air dates"
        case .imdbPeople: "Search IMDb actors, directors, writers, and their filmographies"
        case .imdbFranchises: "Browse curated franchises using the local IMDb title index"
        default: "\(model.visibleItems.count) titles · From \(model.catalogName)"
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DenboxMark()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DENBOX")
                        .font(.denbox(size: 13, weight: .heavy))
                        .tracking(1.8)
                    Text("MOVIES & SERIES")
                        .font(.denbox(size: 8, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 28)

            Text("LIBRARY")
                .font(.denbox(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Color.secondaryText.opacity(0.85))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(LibrarySection.allCases) { item in
                    Button {
                        model.section = item
                        model.searchText = ""
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.denbox(size: 15, weight: .medium))
                                .frame(width: 21)
                            Text(item.displayName)
                                .font(.denbox(size: 13, weight: model.section == item ? .semibold : .regular))
                            Spacer()
                            let count: Int? = switch item {
                            case .movies: model.items.filter { $0.kind == "Movie" }.count
                            case .shows: model.items.filter { $0.kind == "Series" }.count
                            case .watchlist: model.savedIDs.count
                            case .myRatings: model.personalRatings.count
                            default: nil
                            }
                            if let count, count > 0 {
                                Text("\(count)")
                                    .font(.denbox(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.secondaryText)
                            }
                        }
                        .foregroundStyle(model.section == item ? .white : Color.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(model.section == item ? Color.white.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.denbox(size: 26))
                    .foregroundStyle(Color.white.opacity(0.75))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.catalogName)
                        .font(.denbox(size: 12, weight: .medium))
                    Text(DenboxLanguage.localizedMessage(model.connectionStatus))
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button { model.showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.denbox(size: 15))
                        .foregroundStyle(Color.secondaryText)
                }
                .buttonStyle(.plain)
                .help(DenboxLanguage.localizedMessage("Catalog settings"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 17)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        }
        .background(Color.sidebar)
        .toolbarBackground(Color.sidebar, for: .windowToolbar)
    }
}

private struct DenboxMark: View {
    var body: some View {
        Image("Denbox-Icon")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: Color.orange.opacity(0.20), radius: 8, y: 3)
    }
}

private struct HeroFeature: View {
    @EnvironmentObject private var model: LibraryModel
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .leading) {
            HeroArtwork(palette: item.palette)
            if let url = item.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            LinearGradient(colors: [.black.opacity(0.76), .black.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                    Text("DENBOX PICKS")
                        .tracking(1.7)
                }
                .font(.denbox(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.83))
                .padding(.bottom, 13)

                Text(item.title)
                    .font(.denbox(size: 39, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(item.subtitle)
                    .font(.denbox(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.top, 5)
                Text(item.synopsis)
                    .font(.denbox(size: 13))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(2)
                    .frame(maxWidth: 430, alignment: .leading)
                    .padding(.top, 14)

                HStack(spacing: 11) {
                    Button { model.selectedItem = item } label: {
                        Label("View Details", systemImage: "play.fill")
                            .font(.denbox(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .background(.white, in: Capsule())

                    Button { model.toggleSaved(item) } label: {
                        Label(model.savedIDs.contains(item.id) ? "In My List" : "Add to My List",
                              systemImage: model.savedIDs.contains(item.id) ? "checkmark" : "plus")
                            .font(.denbox(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.17), in: Capsule())
                }
                .padding(.top, 19)
            }
            .padding(.leading, 36)
            .padding(.vertical, 30)
        }
        .frame(height: 310)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text(LocalizedStringKey(item.isRemote ? "FROM YOUR CATALOG" : "SAMPLE ARTWORK"))
                .font(.denbox(size: 8, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(14)
        }
    }
}

private struct HeroArtwork: View {
    let palette: Int
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(colors: Palette.colors(palette), startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: h * 0.82)
                    .blur(radius: 1)
                    .position(x: w * 0.76, y: h * 0.42)
                Circle()
                    .fill(Palette.colors(palette).first!.opacity(0.68))
                    .frame(width: h * 0.75)
                    .blur(radius: 2)
                    .position(x: w * 0.82, y: h * 0.9)
                Image(systemName: "sun.horizon.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white.opacity(0.32))
                    .frame(width: h * 0.84)
                    .position(x: w * 0.74, y: h * 0.54)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: w, height: h)
        }
    }
}

private struct MediaShelf: View {
    @EnvironmentObject private var model: LibraryModel
    let title: String
    let subtitle: String
    let items: [MediaItem]
    var landscape = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DenboxLanguage.localizedMessage(title))
                        .font(.denbox(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(DenboxLanguage.localizedMessage(subtitle))
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if title == "Movies" || title == "TV Shows" {
                    Button {
                        model.section = title == "Movies" ? .movies : .shows
                        model.searchText = ""
                    } label: {
                        HStack(spacing: 7) {
                            Text("See all")
                            Image(systemName: "chevron.right")
                        }
                        .font(.denbox(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        Button { model.selectedItem = item } label: {
                            if landscape { LandscapeCard(item: item) } else {
                                PosterCard(item: item, personalRating: model.personalRatings[item.id]?.rating)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(model.savedIDs.contains(item.id) ? "Remove from My List" : "Add to My List", systemImage: "bookmark") {
                                model.toggleSaved(item)
                            }
                            Button("Details", systemImage: "info.circle") { model.selectedItem = item }
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct PosterCard: View {
    let item: MediaItem
    let personalRating: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                CardArtwork(item: item)
                    .frame(width: 160, height: 216)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if let personalRating {
                            Label("\(personalRating)", systemImage: "star.fill")
                                .font(.denbox(size: 10, weight: .bold))
                                .foregroundStyle(Color.yellow)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.72), in: Capsule())
                                .padding(9)
                        }
                    }
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedStringKey(item.kind.uppercased()))
                        .font(.denbox(size: 8, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.74))
                    Text(item.title)
                        .font(.denbox(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(13)
                Image(systemName: item.symbol)
                    .font(.denbox(size: 31, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(item.year.isEmpty ? item.subtitle : "\(item.year) · \(item.subtitle)")
                .font(.denbox(size: 10))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 160, alignment: .leading)
    }
}

private struct LandscapeCard: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                CardArtwork(item: item)
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 12) {
                    Image(systemName: item.symbol)
                        .font(.denbox(size: 22, weight: .light))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.denbox(size: 13, weight: .bold)).lineLimit(1)
                        Text([item.year, DenboxLanguage.localizedMediaKind(item.kind)]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.denbox(size: 10))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(13)
            }
            .frame(width: 290, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .frame(width: 290)
    }
}

private struct CardArtwork: View {
    let item: MediaItem
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: Palette.colors(item.palette), startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: min(size.width, size.height) * 0.82)
                    .blur(radius: 1)
                    .offset(x: size.width * 0.26, y: -size.height * 0.18)
                Circle()
                    .fill(Color.black.opacity(0.20))
                    .frame(width: min(size.width, size.height) * 0.8)
                    .offset(x: -size.width * 0.3, y: size.height * 0.42)
                Image(systemName: item.symbol)
                    .font(.denbox(size: min(size.width, size.height) * 0.29, weight: .ultraLight))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .offset(x: size.width * 0.19, y: -size.height * 0.06)
                if let url = item.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
            .clipped()
            .frame(width: size.width, height: size.height)
        }
    }
}

private enum Palette {
    static func colors(_ index: Int) -> [Color] {
        let colors: [[Color]] = [
            [Color(red: 0.08, green: 0.29, blue: 0.43), Color(red: 0.91, green: 0.49, blue: 0.29)],
            [Color(red: 0.12, green: 0.16, blue: 0.40), Color(red: 0.26, green: 0.68, blue: 0.72)],
            [Color(red: 0.18, green: 0.31, blue: 0.49), Color(red: 0.73, green: 0.85, blue: 0.89)],
            [Color(red: 0.31, green: 0.16, blue: 0.42), Color(red: 0.89, green: 0.49, blue: 0.52)],
            [Color(red: 0.84, green: 0.40, blue: 0.22), Color(red: 0.33, green: 0.22, blue: 0.54)],
            [Color(red: 0.13, green: 0.25, blue: 0.29), Color(red: 0.68, green: 0.62, blue: 0.46)],
            [Color(red: 0.07, green: 0.29, blue: 0.42), Color(red: 0.31, green: 0.68, blue: 0.75)],
            [Color(red: 0.37, green: 0.25, blue: 0.50), Color(red: 0.91, green: 0.64, blue: 0.40)]
        ]
        return colors[abs(index) % colors.count]
    }
}

private struct IMDbPeoplePage: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var query = ""
    @State private var results: [IMDbPersonMetadata] = []
    @State private var selectedPerson: IMDbPersonMetadata?
    @State private var credits: [IMDbPersonCredit] = []
    @State private var isLoadingCredits = false
    @State private var hasMoreCredits = false
    @State private var autoSelectExactName = false
    @State private var pendingPersonImageURL: URL?
    private let pageSize = 100
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selectedPerson {
                personDetail(selectedPerson)
            } else {
                searchPanel
            }
        }
        .onAppear {
            model.refreshIMDbPeopleAvailability()
            consumePendingPersonRequest()
        }
        .onChange(of: model.pendingIMDbPersonRequest) { _ in
            consumePendingPersonRequest()
        }
        .task(id: query) {
            guard selectedPerson == nil else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { results = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                IMDbMetadataStore.shared.searchPeople(trimmed)
            }.value
            guard !Task.isCancelled else { return }
            results = found
            if autoSelectExactName {
                autoSelectExactName = false
                let target = MediaTitleMatching.normalize(trimmed)
                let exactMatches = found.filter {
                    MediaTitleMatching.normalize($0.name) == target
                }
                if exactMatches.count == 1, let exact = exactMatches.first {
                    let imageURL = pendingPersonImageURL
                    pendingPersonImageURL = nil
                    select(exact, imageURL: imageURL)
                }
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondaryText)
                TextField("Search actors, directors, writers…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.denbox(size: 15))
                    .onSubmit { searchNow() }
                if !query.isEmpty {
                    Button { query = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(13)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))

            if !model.imdbPeopleAvailable {
                VStack(alignment: .leading, spacing: 11) {
                    Label("IMDb people data is not indexed yet", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.denbox(size: 15, weight: .semibold))
                    Text("Download the IMDb name, cast, and crew datasets from Settings to enable local people search and filmographies.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                    Button("Open settings and download IMDb data", systemImage: "arrow.down.circle") {
                        model.showingSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Text("Type at least two letters to search IMDb people.")
                    .font(.denbox(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .padding(.vertical, 14)
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.denbox(size: 26, weight: .ultraLight))
                    Text("No IMDb people matched \(query).")
                        .font(.denbox(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Text("\(results.count) people · from IMDb's local name index")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(results) { person in
                        Button { select(person) } label: {
                            personCard(person)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func personCard(_ person: IMDbPersonMetadata) -> some View {
        HStack(spacing: 12) {
            personPortrait(person, width: 48, height: 54, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 5) {
                Text(person.name)
                    .font(.denbox(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(person.professions.prefix(3).map(DenboxLanguage.localizedProfession).joined(separator: " · "))
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                Text(person.lifeYears)
                    .font(.denbox(size: 9))
                    .foregroundStyle(Color.secondaryText.opacity(0.8))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.denbox(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
        }
        .padding(11)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
    }

    private func personDetail(_ person: IMDbPersonMetadata) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Button {
                selectedPerson = nil
                credits = []
            } label: {
                Label("Back to people search", systemImage: "chevron.left")
                    .font(.denbox(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondaryText)

            HStack(spacing: 14) {
                personPortrait(person, width: 72, height: 78, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text(person.name)
                        .font(.denbox(size: 24, weight: .bold))
                    Text(person.professions.prefix(3).map(DenboxLanguage.localizedProfession).joined(separator: " · "))
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.secondaryText)
                    Text(person.lifeYears)
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if let url = person.imdbURL {
                    Link("IMDb profile", destination: url)
                        .font(.denbox(size: 11, weight: .medium))
                }
            }

            HStack {
                Text("Filmography")
                    .font(.denbox(size: 19, weight: .bold))
                Spacer()
                Text("IMDb principal cast and crew credits")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
            }
            if credits.isEmpty && isLoadingCredits {
                ProgressView("Loading credits…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if credits.isEmpty {
                Text("No movie or TV credits were found for this person in the current IMDb dataset.")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(credits) { credit in
                        IMDbPersonCreditRow(credit: credit)
                    }
                }
                if hasMoreCredits {
                    Button {
                        Task { await loadMoreCredits(for: person) }
                    } label: {
                        if isLoadingCredits { ProgressView().controlSize(.small) }
                        else { Label("Load more credits", systemImage: "arrow.down.circle") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingCredits)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func personPortrait(_ person: IMDbPersonMetadata, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        if let imageURL = person.imageURL {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    personPortraitPlaceholder(person, cornerRadius: cornerRadius)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            personPortraitPlaceholder(person, cornerRadius: cornerRadius)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    private func personPortraitPlaceholder(_ person: IMDbPersonMetadata, cornerRadius: CGFloat) -> some View {
        Image(systemName: "person.crop.square")
            .font(.denbox(size: 30, weight: .ultraLight))
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: Palette.colors(person.nconst.hashValue), startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func searchNow() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        Task {
            results = await Task.detached(priority: .userInitiated) {
                IMDbMetadataStore.shared.searchPeople(trimmed)
            }.value
        }
    }

    private func consumePendingPersonRequest() {
        guard let request = model.consumePendingIMDbPersonRequest() else { return }
        selectedPerson = nil
        credits = []
        results = []
        pendingPersonImageURL = request.imageURL
        if let nconst = request.nconst {
            query = ""
            autoSelectExactName = false
            Task {
                let person = await Task.detached(priority: .userInitiated) {
                    IMDbMetadataStore.shared.person(for: nconst)
                }.value
                guard model.section == .imdbPeople else { return }
                if let person {
                    pendingPersonImageURL = nil
                    select(person, imageURL: request.imageURL)
                } else {
                    autoSelectExactName = true
                    query = request.name
                }
            }
        } else {
            autoSelectExactName = true
            query = request.name
        }
    }

    private func select(_ candidate: IMDbPersonMetadata, imageURL: URL? = nil) {
        let person = candidate.usingImage(imageURL)
        selectedPerson = person
        credits = []
        hasMoreCredits = false
        isLoadingCredits = true
        Task {
            let firstPage = await Task.detached(priority: .userInitiated) {
                IMDbMetadataStore.shared.personCredits(for: person.nconst, offset: 0, limit: pageSize)
            }.value
            guard selectedPerson?.nconst == person.nconst else { return }
            credits = firstPage
            hasMoreCredits = firstPage.count == pageSize
            isLoadingCredits = false
        }
    }

    private func loadMoreCredits(for person: IMDbPersonMetadata) async {
        guard !isLoadingCredits else { return }
        isLoadingCredits = true
        let nextOffset = credits.count
        let nextPage = await Task.detached(priority: .userInitiated) {
            IMDbMetadataStore.shared.personCredits(for: person.nconst, offset: nextOffset, limit: pageSize)
        }.value
        guard selectedPerson?.nconst == person.nconst else { isLoadingCredits = false; return }
        credits.append(contentsOf: nextPage)
        hasMoreCredits = nextPage.count == pageSize
        isLoadingCredits = false
    }
}

private extension IMDbPersonMetadata {
    var lifeYears: String {
        let birth = birthYear.map(String.init)
        let death = deathYear.map(String.init)
        return switch (birth, death) {
        case let (birth?, death?): "\(birth)–\(death)"
        case let (birth?, nil): "Born \(birth)"
        case let (nil, death?): "Died \(death)"
        default: ""
        }
    }
}

private struct IMDbPersonCreditRow: View {
    @EnvironmentObject private var model: LibraryModel
    let credit: IMDbPersonCredit
    @State private var artworkData: Data?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: Palette.colors((credit.title.votes ?? 0) % 8), startPoint: .topLeading, endPoint: .bottomTrailing))
                if let artworkData, let image = NSImage(data: artworkData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 55, height: 68)
                        .clipped()
                } else {
                    Image(systemName: credit.title.kind == "Movie" ? "film" : "tv")
                        .font(.denbox(size: 19, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 55, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                Task { await model.openCatalogTitle(matching: credit.title) }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(credit.title.title)
                            .font(.denbox(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let rating = credit.title.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.denbox(size: 9, weight: .medium))
                                .foregroundStyle(Color.yellow.opacity(0.9))
                        }
                    }
                    Text([credit.title.year.map(String.init), DenboxLanguage.localizedMediaKind(credit.title.kind),
                          DenboxLanguage.localizedProfession(credit.category)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                    if let characters = credit.characters, !characters.isEmpty {
                        Text(characters)
                            .font(.denbox(size: 10))
                            .foregroundStyle(Color.secondaryText.opacity(0.85))
                            .lineLimit(1)
                    } else if let job = credit.job, !job.isEmpty {
                        Text(job)
                            .font(.denbox(size: 10))
                            .foregroundStyle(Color.secondaryText.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(DenboxLanguage.localizedMessage("Search this title in the Simba catalog"))

            if let url = credit.title.imdbURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.denbox(size: 12))
                }
                .help(DenboxLanguage.localizedMessage("Open IMDb title page"))
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .task(id: credit.title.tconst) {
            artworkData = await model.loadIMDbArtwork(for: credit.title)
        }
    }
}

private struct IMDbFranchisesPage: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var selectedFranchiseID = IMDbFranchiseCatalog.all.first?.id ?? ""
    @State private var search = ""
    @State private var titles: [IMDbTitleMetadata] = []
    @State private var isLoading = false
    private let titleColumns = [GridItem(.adaptive(minimum: 145), spacing: 16, alignment: .top)]

    private var visibleFranchises: [IMDbFranchiseDefinition] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return IMDbFranchiseCatalog.all }
        return IMDbFranchiseCatalog.all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selectedFranchise: IMDbFranchiseDefinition? {
        IMDbFranchiseCatalog.all.first { $0.id == selectedFranchiseID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("IMDb Franchises")
                    .font(.denbox(size: 25, weight: .bold))
                Text("Browse curated film and series collections, all inside Denbox.")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.secondaryText)
                        TextField("Find a franchise", text: $search)
                            .textFieldStyle(.plain)
                    }
                    .font(.denbox(size: 12))
                    .padding(10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 5) {
                            ForEach(visibleFranchises) { franchise in
                                Button { selectedFranchiseID = franchise.id } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: selectedFranchiseID == franchise.id ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                                            .font(.denbox(size: 12))
                                            .foregroundStyle(selectedFranchiseID == franchise.id ? Color.accentColor : Color.secondaryText)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(franchise.name)
                                                .font(.denbox(size: 11, weight: .medium))
                                                .lineLimit(1)
                                                .foregroundStyle(.white)
                                            Text("\(franchise.entries.count) titles")
                                                .font(.denbox(size: 9))
                                                .foregroundStyle(Color.secondaryText)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selectedFranchiseID == franchise.id ? Color.white.opacity(0.10) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 555)
                    .scrollIndicators(.hidden)
                }
                .frame(width: 220)

                VStack(alignment: .leading, spacing: 12) {
                    if let franchise = selectedFranchise {
                        Text(franchise.name)
                            .font(.denbox(size: 20, weight: .bold))
                        Text(DenboxLanguage.localizedMessage(franchise.summary))
                            .font(.denbox(size: 11))
                            .foregroundStyle(Color.secondaryText)
                            Text("Titles are matched against the local IMDb dataset. Select one to find it in the Simba catalog.")
                            .font(.denbox(size: 10))
                            .foregroundStyle(Color.secondaryText.opacity(0.9))
                            .padding(.bottom, 4)

                        if isLoading {
                            ProgressView("Loading local titles…")
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else if titles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("No matching titles in the local IMDb index", systemImage: "film.stack")
                                    .font(.denbox(size: 13, weight: .semibold))
                                Text("Refresh IMDb data in Settings, then reopen this collection.")
                                    .font(.denbox(size: 10))
                                    .foregroundStyle(Color.secondaryText)
                                Button("Open Settings", systemImage: "gearshape") {
                                    model.showingSettings = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            LazyVGrid(columns: titleColumns, alignment: .leading, spacing: 18) {
                                ForEach(titles) { title in
                                    Button {
                                        Task { await model.openCatalogTitle(matching: title) }
                                    } label: {
                                        IMDbTitleCard(metadata: title, width: 145, artworkHeight: 195)
                                    }
                                    .buttonStyle(.plain)
                                .help("Find \(title.title) in Simba")
                                }
                            }
                        }

                        if let message = model.similarTitleSearchMessage {
                            Text(DenboxLanguage.localizedMessage(message))
                                .font(.denbox(size: 10))
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            if selectedFranchise == nil, let first = IMDbFranchiseCatalog.all.first {
                selectedFranchiseID = first.id
            }
        }
        .task(id: selectedFranchiseID) {
            guard !selectedFranchiseID.isEmpty else { titles = []; return }
            let franchiseID = selectedFranchiseID
            isLoading = true
            titles = await Task.detached(priority: .userInitiated) {
                IMDbMetadataStore.shared.franchiseTitles(for: franchiseID)
            }.value
            isLoading = false
        }
    }
}

private struct GenreFilterBar: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                genreChip(title: DenboxLanguage.localizedMessage("All"), selected: model.selectedGenreFilters.isEmpty) {
                    model.clearGenreFilters()
                }
                ForEach(model.genreFacets) { facet in
                    genreChip(title: facet.displayName, selected: model.selectedGenreFilters.contains(facet.name)) {
                        model.toggleGenreFilter(facet.name)
                    }
                    .help(DenboxLanguage.localizedMessage("Filter genre: \(facet.name)"))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func genreChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.denbox(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .black : Color.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.white : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct GenresPage: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var selectedGenre: String?
    private let columns = [GridItem(.adaptive(minimum: 175), spacing: 12)]

    var body: some View {
        Group {
            if let selectedGenre {
                IMDbGenreTitlesPage(genre: selectedGenre) {
                    self.selectedGenre = nil
                }
            } else {
                genrePicker
            }
        }
    }

    private var genrePicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Favorite genres")
                    .font(.denbox(size: 21, weight: .bold))
                Text("Click a genre to browse matching titles. Use the star to tune recommendations.")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }
            if model.genreFacets.isEmpty {
                VStack(spacing: 11) {
                    if model.isUpdatingIMDbDataset || model.isLoadingGenreFacets {
                        ProgressView("Preparing genres…")
                            .tint(.white)
                    } else {
                        Text(DenboxLanguage.localizedMessage(model.hasIMDbData
                             ? "IMDb data is available, but the genre list could not be prepared. Try again."
                             : "Download IMDb data to build the genre list."))
                            .font(.denbox(size: 12))
                            .foregroundStyle(Color.secondaryText)
                        Button(DenboxLanguage.localizedMessage(model.hasIMDbData ? "Try again" : "Download IMDb data"),
                               systemImage: model.hasIMDbData ? "arrow.clockwise" : "arrow.down.circle") {
                            Task {
                                if model.hasIMDbData { await model.loadGenreFacets() }
                                else { await model.refreshIMDbDataset() }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .disabled(model.isUpdatingIMDbDataset)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(model.genreFacets) { facet in
                        let selected = model.preferredGenres.contains(facet.name)
                        HStack(spacing: 12) {
                            Button { selectedGenre = facet.name } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(facet.displayName)
                                        .font(.denbox(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(DenboxLanguage.localizedMessage("\(facet.titleCount.formatted()) titles in IMDb · \(facet.name)"))
                                        .font(.denbox(size: 9))
                                        .foregroundStyle(Color.secondaryText)
                                }
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Button { model.togglePreferredGenre(facet.name) } label: {
                                Image(systemName: selected ? "star.fill" : "star")
                                    .font(.denbox(size: 15, weight: .semibold))
                                    .foregroundStyle(selected ? Color.yellow : Color.secondaryText)
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(DenboxLanguage.localizedMessage("Use genre for recommendations"))
                        }
                        .padding(13)
                        .background(selected ? Color.white.opacity(0.1) : Color.white.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }
            if !model.selectedGenreFilters.isEmpty {
                Button("Clear genre filters", systemImage: "xmark.circle") {
                    model.clearGenreFilters()
                }
                .buttonStyle(.bordered)
            }
        }
        .task { await model.loadGenreFacets() }
    }
}

private struct IMDbGenreTitlesPage: View {
    @EnvironmentObject private var model: LibraryModel
    let genre: String
    let onBack: () -> Void

    @State private var selectedKind = "Any"
    @State private var searchText = ""
    @State private var titles: [IMDbTitleMetadata] = []
    @State private var nextOffset = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var requestID = UUID()

    private let pageSize = 60
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 16, alignment: .top)]

    private var filteredTitles: [IMDbTitleMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return titles }
        return titles.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button("All genres", systemImage: "chevron.left", action: onBack)
                    .buttonStyle(.plain)
                Spacer()
                Text(IMDbGenreLocalization.displayName(for: genre))
                    .font(.denbox(size: 22, weight: .bold))
            }

            Text("Titles from IMDb, sorted by rating and votes. Selecting one searches Simba.")
                .font(.denbox(size: 11))
                .foregroundStyle(Color.secondaryText)

            Picker("Title type", selection: $selectedKind) {
                Text("All").tag("Any")
                Text("Movies").tag("Movie")
                Text("TV series").tag("Series")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)

            TextField("Search within this genre", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 460)

            HStack {
                Text("\(filteredTitles.count.formatted()) IMDb titles loaded")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
                Spacer()
                Text("IMDb")
                    .font(.denbox(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
            }

            if titles.isEmpty && isLoading {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Loading IMDb titles…")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else if filteredTitles.isEmpty {
                Text(searchText.isEmpty
                     ? "No rated IMDb titles were found for this genre."
                     : "No titles on the loaded pages match this search.")
                    .font(.denbox(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(Array(filteredTitles.enumerated()), id: \.element.id) { index, title in
                        Button {
                            Task { await model.openCatalogTitle(matching: title) }
                        } label: {
                            IMDbTitleCard(metadata: title, rank: index + 1, width: 155, artworkHeight: 210)
                        }
                        .buttonStyle(.plain)
                        .help("Search in Simba and open")
                    }
                }
            }

            if hasMore || isLoading {
                Button("Load more IMDb titles", systemImage: "arrow.down.circle") {
                    Task { await loadNextPage(reset: false) }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || !hasMore)
            }

            if let message = model.similarTitleSearchMessage {
                Text(DenboxLanguage.localizedMessage(message))
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .task(id: "\(genre)|\(selectedKind)") {
            await loadNextPage(reset: true)
        }
    }

    @MainActor
    private func loadNextPage(reset: Bool) async {
        guard !isLoading || reset else { return }
        let kind = selectedKind == "Any" ? nil : selectedKind
        let offset = reset ? 0 : nextOffset
        let generation = UUID()
        requestID = generation
        isLoading = true
        if reset {
            titles = []
            nextOffset = 0
            hasMore = true
        }
        let page = await Task.detached(priority: .userInitiated) {
            IMDbMetadataStore.shared.genreTitles(named: genre, kind: kind, offset: offset, limit: pageSize)
        }.value
        guard requestID == generation else { return }
        isLoading = false
        guard !Task.isCancelled else { return }
        if reset { titles = page } else { titles.append(contentsOf: page) }
        nextOffset = offset + page.count
        hasMore = page.count == pageSize
    }
}

private struct PersonalizedRecommendationsPage: View {
    @EnvironmentObject private var model: LibraryModel
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("For You")
                    .font(.denbox(size: 21, weight: .bold))
                Text("IMDb ratings and votes are combined with your personal star ratings, viewing history, and preferred genres. This ranking is calculated locally.")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }
            if !model.preferredGenres.isEmpty {
                HStack(spacing: 7) {
                    Text("Your taste:")
                        .font(.denbox(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                    ForEach(model.genreFacets.filter { model.preferredGenres.contains($0.name) }) { facet in
                        Text(facet.displayName)
                            .font(.denbox(size: 10, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.09), in: Capsule())
                    }
                }
            }
            if model.isLoadingRecommendations {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Building recommendations from IMDb…")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else if model.recommendations.isEmpty {
                VStack(spacing: 11) {
                    Text(DenboxLanguage.localizedMessage(model.hasIMDbData
                         ? "No suitable titles were found in the current IMDb data. Change your genres or try again."
                         : "Download IMDb data to get movie and series recommendations."))
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.secondaryText)
                    if model.hasIMDbData {
                        Button("Refresh recommendations", systemImage: "arrow.clockwise") {
                            Task { await model.refreshDiscoveryData() }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Download IMDb data", systemImage: "arrow.down.circle") {
                            Task { await model.refreshIMDbDataset() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .disabled(model.isUpdatingIMDbDataset)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(Array(model.recommendations.enumerated()), id: \.element.id) { index, title in
                        Button {
                            Task { await model.openCatalogTitle(matching: title) }
                        } label: {
                            IMDbTitleCard(metadata: title, rank: index + 1, width: 155, artworkHeight: 210)
                        }
                        .buttonStyle(.plain)
                        .help("Search in Simba and open")
                    }
                }
            }
        }
        .task {
            if model.genreFacets.isEmpty || model.recommendations.isEmpty {
                await model.refreshDiscoveryData()
            }
        }
    }
}

private struct ContinueWatchingPage: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let message = model.viewingUpdateMessage {
                Text(DenboxLanguage.localizedMessage(message))
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.orange)
            }
            if model.continueWatchingItems.isEmpty {
                Text("Movies and episodes you start will stay here so you can continue watching later.")
                    .font(.denbox(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(model.continueWatchingItems) { progress in
                        WatchProgressCard(progress: progress)
                    }
                }
            }
        }
        .onAppear { model.refreshViewingData() }
    }
}

private struct WatchProgressCard: View {
    @EnvironmentObject private var model: LibraryModel
    let progress: WatchProgress

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task { await model.resume(progress) }
            } label: {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: Palette.colors(abs(progress.mediaID.hashValue) % 8),
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let url = progress.artworkURL {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                            .frame(width: 92, height: 64)
                            .clipped()
                    } else {
                        Image(systemName: progress.kind == "Series" ? "tv" : "film")
                            .font(.denbox(size: 24, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    if let duration = progress.durationSeconds, duration > 0 {
                        ProgressView(value: progress.progress)
                            .tint(.red)
                            .padding(.horizontal, 2)
                    }
                }
                .frame(width: 92, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(progress.mediaTitle)
                    .font(.denbox(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                Button {
                    model.openProgressTitle(progress)
                } label: {
                    Text(progress.displayTitle)
                        .font(.denbox(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(progress.mediaID.hasPrefix("local:"))
                .help(DenboxLanguage.localizedMessage(progress.kind == "Series"
                    ? "Open this episode in its series"
                    : "Open title details"))
                if let duration = progress.durationSeconds, duration > 0 {
                    ProgressView(value: progress.progress)
                        .tint(.red)
                    Text(DenboxLanguage.localizedMessage("Watched \(watchTimeLabel(progress.positionSeconds)) of \(watchTimeLabel(duration))"))
                        .font(.denbox(size: 9))
                        .foregroundStyle(Color.secondaryText)
                } else {
                    Text(DenboxLanguage.localizedMessage("Resume at \(watchTimeLabel(progress.positionSeconds))"))
                        .font(.denbox(size: 9))
                        .foregroundStyle(Color.secondaryText)
                }
            }
            Spacer(minLength: 5)
            Button {
                Task { await model.resume(progress) }
            } label: {
                if model.isResumingPlayback {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(DenboxLanguage.localizedMessage("Opening playback…"))
                    }
                } else {
                    Label("Resume", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(model.isResumingPlayback)
            Button("Mark as watched", systemImage: "checkmark") {
                model.setWatched(progress, watched: true)
            }
            .buttonStyle(.bordered)
        }
        .padding(11)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WatchHistoryPage: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.viewingUpdateMessage {
                Text(DenboxLanguage.localizedMessage(message)).font(.denbox(size: 11)).foregroundStyle(Color.orange)
            }
            if model.watchHistory.isEmpty {
                Text("Playback sessions for movies and episodes on this Mac will appear here.")
                    .font(.denbox(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } else {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(model.watchHistory) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.kind == "Series" ? "tv" : "film")
                                .font(.denbox(size: 17, weight: .light))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(width: 42, height: 42)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.displayTitle)
                                    .font(.denbox(size: 13, weight: .semibold))
                                Text([entry.mediaTitle == entry.displayTitle ? nil : entry.mediaTitle,
                                      entry.episodeLabel,
                                      entry.startedAt.formatted(date: .abbreviated, time: .shortened),
                                      entry.playerKind]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.denbox(size: 9))
                                    .foregroundStyle(Color.secondaryText)
                                Text(DenboxLanguage.localizedMessage("Watch time: \(watchTimeLabel(entry.watchedSeconds))"))
                                    .font(.denbox(size: 9))
                                    .foregroundStyle(Color.secondaryText.opacity(0.85))
                            }
                            Spacer(minLength: 4)
                            Button {
                                Task { await model.resume(entry) }
                            } label: {
                                if model.isResumingPlayback {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text(DenboxLanguage.localizedMessage("Opening playback…"))
                                    }
                                } else {
                                    Label("Resume", systemImage: "play.fill")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isResumingPlayback)
                        }
                        .padding(11)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }
        }
        .onAppear { model.refreshViewingData() }
    }
}

private struct ViewingStatsPage: View {
    @EnvironmentObject private var model: LibraryModel
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 12)]
    @State private var isConfirmingClear = false
    @State private var importPreview: ViewingDataImportPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let message = model.viewingUpdateMessage {
                Text(DenboxLanguage.localizedMessage(message)).font(.denbox(size: 11)).foregroundStyle(Color.secondaryText)
            }
            if model.isLoadingViewingStats {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                statCard(title: "Total watch time", value: DenboxLanguage.localizedMessage(String(format: "%.1f hours", model.viewingStats.watchedHours)), symbol: "clock")
                statCard(title: "Movies completed", value: "\(model.viewingStats.completedMovies)", symbol: "film")
                statCard(title: "Episodes completed", value: "\(model.viewingStats.completedEpisodes)", symbol: "tv")
                statCard(title: "Playback sessions", value: "\(model.viewingStats.sessionCount)", symbol: "play.rectangle")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Most watched genres")
                    .font(.denbox(size: 17, weight: .bold))
                if model.viewingStats.favoriteGenres.isEmpty {
                    Text("Genre statistics will appear here after you watch something.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                } else {
                    ForEach(Array(model.viewingStats.favoriteGenres.prefix(10).enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 9) {
                            Text("\(index + 1).")
                                .font(.denbox(size: 10, weight: .bold))
                                .foregroundStyle(Color.secondaryText)
                                .frame(width: 22, alignment: .leading)
                            Text(IMDbGenreLocalization.displayName(for: entry.name))
                                .font(.denbox(size: 12, weight: .medium))
                            Spacer()
                            Text(DenboxLanguage.localizedMessage(String(format: "%.1f hours", entry.seconds / 3600)))
                                .font(.denbox(size: 10))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(17)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))

            HStack(spacing: 10) {
                Button(action: importViewingActivity) {
                    Label("Import JSON…", systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.bordered)
                .help("Merge a viewing-data backup into this Mac.")
                .disabled(model.isTrackingPlayback)

                Button(action: exportViewingActivity) {
                    Label("Export JSON…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("JSON backups may include local file paths for videos opened directly from this Mac.")

                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("Clear history", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(model.isTrackingPlayback)
            }
            Text("Backups include watch progress, personal ratings, watch time, and title details. Import merges data and keeps newer local progress and ratings.")
                .font(.denbox(size: 10))
                .foregroundStyle(Color.secondaryText)
            Text("JSON backups may include local file paths for videos opened directly from this Mac. Choose a destination you trust.")
                .font(.denbox(size: 10))
                .foregroundStyle(Color.secondaryText)
            if model.isTrackingPlayback {
                Text("Close active playback before clearing viewing data.")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .onAppear { model.refreshViewingStats(force: true) }
        .sheet(item: $importPreview) { preview in
            VStack(alignment: .leading, spacing: 16) {
                Text("Review viewing-data import")
                    .font(.denbox(size: 19, weight: .bold))
                Text(preview.fileName)
                    .font(.denbox(size: 12, weight: .medium))
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: 7) {
                    Text(DenboxLanguage.localizedMessage("Progress records: \(preview.export.progress.count)"))
                    Text(DenboxLanguage.localizedMessage("History sessions: \(preview.export.history.count)"))
                    Text(DenboxLanguage.localizedMessage("Personal ratings: \(preview.export.personalRatings.count)"))
                }
                .font(.denbox(size: 12))
                Text("Newer local progress and ratings will be kept. Duplicate history sessions will be skipped. Nothing will be deleted.")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { importPreview = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Merge data") {
                        if model.mergeViewingData(preview.export) { importPreview = nil }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 460)
        }
        .alert("Clear viewing history?", isPresented: $isConfirmingClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { model.clearViewingActivity() }
        } message: {
            Text("This will delete the watch history, resume progress, and local stats on this Mac. This cannot be undone.")
        }
    }

    private func exportViewingActivity() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.title = DenboxLanguage.localizedMessage("Export viewing data")
        panel.prompt = DenboxLanguage.localizedMessage("Save")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Denbox-viewing-data-\(formatter.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportViewingActivity(to: url)
    }

    private func importViewingActivity() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = DenboxLanguage.localizedMessage("Import viewing data")
        panel.prompt = DenboxLanguage.localizedMessage("Review import")
        guard panel.runModal() == .OK, let url = panel.url,
              let preview = model.prepareViewingDataImport(from: url) else { return }
        importPreview = preview
    }

    private func statCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol)
                .font(.denbox(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(value)
                .font(.denbox(size: 24, weight: .bold))
            Text(DenboxLanguage.localizedMessage(title))
                .font(.denbox(size: 10))
                .foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 95, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

private func watchTimeLabel(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    let hours = value / 3600
    let minutes = (value % 3600) / 60
    let remaining = value % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
    return String(format: "%d:%02d", minutes, remaining)
}

@MainActor
private final class DiscoveryFeedsModel: ObservableObject {
    @Published private(set) var popularTitles: [TrendingTitle] = []
    @Published private(set) var boxOfficeEntries: [BoxOfficeRecord] = []
    @Published private(set) var releaseEvents: [DiscoveryCalendarEvent] = []
    @Published private(set) var popularError: String?
    @Published private(set) var boxOfficeError: String?
    @Published private(set) var calendarMessages: [String] = []
    @Published private(set) var isLoadingPopular = false
    @Published private(set) var isLoadingBoxOffice = false
    @Published private(set) var isLoadingCalendar = false
    @Published private(set) var needsTMDBToken = false
    private var loadedPopularKind: String?
    private var loadedCalendarMonth: String?

    func loadPopular(kind: IMDbTrendingKind, accessToken: String?, force: Bool = false) async {
        guard force || loadedPopularKind != kind.rawValue else { return }
        isLoadingPopular = true
        popularError = nil
        needsTMDBToken = false
        defer { isLoadingPopular = false }
        do {
            popularTitles = try await DiscoveryFeedService.shared.popularToday(kind: kind.mediaKind, accessToken: accessToken, force: force)
            loadedPopularKind = kind.rawValue
        } catch {
            popularTitles = []
            popularError = error.localizedDescription
            if let feedError = error as? DiscoveryFeedError {
                needsTMDBToken = feedError == .noTMDBToken
            }
        }
    }

    func loadBoxOffice(force: Bool = false) async {
        guard force || boxOfficeEntries.isEmpty else { return }
        isLoadingBoxOffice = true
        boxOfficeError = nil
        defer { isLoadingBoxOffice = false }
        do {
            boxOfficeEntries = try await DiscoveryFeedService.shared.boxOffice(force: force)
        } catch {
            boxOfficeError = error.localizedDescription
        }
    }

    func loadCalendar(cacheKey: String, startDate: Date, endDate: Date,
                      releaseMonths: [String], force: Bool = false) async {
        let key = cacheKey
        guard force || loadedCalendarMonth != key else { return }
        isLoadingCalendar = true
        calendarMessages = []
        if loadedCalendarMonth != key { releaseEvents = [] }
        defer { isLoadingCalendar = false }
        let result = await DiscoveryFeedService.shared.releaseCalendar(cacheKey: key, startDate: startDate,
                                                                        endDate: endDate, releaseMonths: releaseMonths,
                                                                        force: force)
        releaseEvents = result.events
        calendarMessages = result.sourceMessages
        loadedCalendarMonth = key
    }
}

private enum IMDbChartTab: String, CaseIterable, Identifiable {
    case topMovies = "Top 250 Movies"
    case topSeries = "Top 250 Series"
    case mostVotedMovies = "Most Voted Movies"
    case mostVotedSeries = "Most Voted Series"
    case trending = "Popular Today"
    case boxOffice = "Box Office"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .topMovies: "Top 250 Movies"
        case .topSeries: "Top 250 Series"
        case .mostVotedMovies: "Most Voted Movies"
        case .mostVotedSeries: "Most Voted Series"
        case .trending: "Popular Today"
        case .boxOffice: "Box Office"
        }
    }
}

private enum IMDbTrendingKind: String, CaseIterable, Identifiable {
    case movies = "Movies"
    case series = "TV Shows"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .movies: "Movies"
        case .series: "TV Shows"
        }
    }

    var chartTitle: LocalizedStringKey {
        switch self {
        case .movies: "Most Popular · Movies"
        case .series: "Most Popular · TV Shows"
        }
    }

    var mediaKind: String { self == .series ? "Series" : "Movie" }
}

private struct IMDbChartsPage: View {
    @EnvironmentObject private var model: LibraryModel
    @StateObject private var feeds = DiscoveryFeedsModel()
    @State private var selectedTab: IMDbChartTab = .topMovies
    @State private var trendingKind: IMDbTrendingKind = .movies
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedTab.displayName)
                    .font(.denbox(size: 23, weight: .bold))
                Text(selectedTab == .trending
                     ? "Today's popular titles are shown inside Denbox from TMDB's daily trending feed."
                     : "Ranked from the local IMDb ratings and votes dataset. Pick a title to find it in Simba.")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }

            Picker("Chart", selection: $selectedTab) {
                ForEach(IMDbChartTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 1000)

            if selectedTab == .boxOffice {
                boxOfficePanel
            } else if selectedTab == .trending {
                trendingPanel
            } else if model.isLoadingIMDbCharts {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Loading local IMDb rankings…")
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else if let lists = model.imdbChartLists {
                let titles = titles(for: lists)
                if titles.isEmpty {
                    emptyDatasetState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                            Button {
                                Task { await model.openCatalogTitle(matching: title) }
                            } label: {
                                IMDbTitleCard(metadata: title, rank: index + 1, width: 155, artworkHeight: 210)
                            }
                            .buttonStyle(.plain)
                            .help("Find this title in the Simba catalog")
                        }
                    }
                    Text("Local rankings use IMDb's public ratings and vote counts. Top 250-style lists approximate IMDb's weighted formula and 25,000-vote minimum; IMDb does not publish its regular-voter filter, so these lists may differ from its official charts.")
                        .font(.denbox(size: 9))
                        .foregroundStyle(Color.secondaryText.opacity(0.85))
                    imdbAttribution
                }
            } else {
                emptyDatasetState
            }
        }
        .task(id: "\(selectedTab.rawValue)-\(trendingKind.rawValue)") {
            await model.loadIMDbCharts()
            if selectedTab == .boxOffice { await feeds.loadBoxOffice() }
            if selectedTab == .trending {
                await feeds.loadPopular(kind: trendingKind, accessToken: SecretVault.read(account: "tmdb-read-access-token"))
            }
        }
    }

    private func titles(for lists: IMDbChartLists) -> [IMDbTitleMetadata] {
        switch selectedTab {
        case .topMovies: lists.topMovies
        case .topSeries: lists.topSeries
        case .mostVotedMovies: lists.mostVotedMovies
        case .mostVotedSeries: lists.mostVotedSeries
        case .trending, .boxOffice: []
        }
    }

    private var emptyDatasetState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.to.line")
                .font(.denbox(size: 28, weight: .light))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("Refresh IMDb data to build these lists")
                .font(.denbox(size: 16, weight: .semibold))
            Text("The current local index may only contain TV series. Refresh imports movie ratings too.")
                .font(.denbox(size: 11))
                .foregroundStyle(Color.secondaryText)
            Button("Download / refresh IMDb data", systemImage: "arrow.clockwise") {
                Task { await model.refreshIMDbDataset() }
            }
            .buttonStyle(.bordered)
            .disabled(model.isUpdatingIMDbDataset)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private var boxOfficePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Lifetime Grosses · Worldwide")
                        .font(.denbox(size: 17, weight: .semibold))
                    Text("Worldwide lifetime gross, loaded inside Denbox from Box Office Mojo")
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Button {
                    Task { await feeds.loadBoxOffice(force: true) }
                } label: {
                    Label("Refresh chart", systemImage: "arrow.clockwise")
                        .font(.denbox(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(feeds.isLoadingBoxOffice)
            }
            if feeds.isLoadingBoxOffice && feeds.boxOfficeEntries.isEmpty {
                feedProgress("Loading Box Office Mojo rankings…")
            } else if let error = feeds.boxOfficeError, feeds.boxOfficeEntries.isEmpty {
                feedError(error, retry: { Task { await feeds.loadBoxOffice(force: true) } })
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(feeds.boxOfficeEntries) { entry in
                        Button {
                            Task { await model.openCatalogTitle(matching: entry.title) }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                IMDbTitleCard(metadata: entry.title, rank: entry.rank, width: 155, artworkHeight: 210)
                                Text("Worldwide gross")
                                    .font(.denbox(size: 9))
                                    .foregroundStyle(Color.secondaryText)
                                Text(entry.worldwideGross)
                                    .font(.denbox(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Find this title in the Simba catalog")
                    }
                }
            }
            Text("Source: Box Office Mojo by IMDbPro · worldwide lifetime gross. Choose a poster to search for the title in Simba.")
                .font(.denbox(size: 9))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
        }
    }

    private var trendingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trendingKind.chartTitle)
                        .font(.denbox(size: 17, weight: .semibold))
                    Text("Daily trending list from TMDB; titles open through the Simba catalog.")
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Button {
                    Task {
                        await feeds.loadPopular(kind: trendingKind,
                                                accessToken: SecretVault.read(account: "tmdb-read-access-token"), force: true)
                    }
                } label: {
                    Label("Refresh chart", systemImage: "arrow.clockwise")
                        .font(.denbox(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(feeds.isLoadingPopular)
            }
            Picker("Trending category", selection: $trendingKind) {
                ForEach(IMDbTrendingKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            if feeds.isLoadingPopular && feeds.popularTitles.isEmpty {
                feedProgress("Loading today's popular titles…")
            } else if let error = feeds.popularError, feeds.popularTitles.isEmpty {
                VStack(spacing: 12) {
                    Text(DenboxLanguage.localizedMessage(error))
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                    if feeds.needsTMDBToken {
                        Button("Open Settings") { model.showingSettings = true }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Refresh chart") {
                            Task {
                                await feeds.loadPopular(kind: trendingKind,
                                                        accessToken: SecretVault.read(account: "tmdb-read-access-token"), force: true)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(Array(feeds.popularTitles.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            Task { await model.openCatalogTitle(matching: entry.metadata) }
                        } label: {
                            IMDbTitleCard(metadata: entry.metadata, rank: index + 1, width: 155,
                                          artworkHeight: 210, fallbackArtworkURL: entry.posterURL)
                        }
                        .buttonStyle(.plain)
                        .help("Find this title in the Simba catalog")
                    }
                }
            }
            Text("Daily popularity from TMDB, not IMDb. TMDB scores are shown for context; this feed is separate from IMDb ratings.")
                .font(.denbox(size: 9))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
            Link("TMDB attribution", destination: URL(string: "https://www.themoviedb.org")!)
                .font(.denbox(size: 9))
        }
    }

    private func feedProgress(_ message: LocalizedStringKey) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text(message).font(.denbox(size: 12)).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }

    private func feedError(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Text(DenboxLanguage.localizedMessage(message))
                .font(.denbox(size: 12))
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            Button("Refresh chart", action: retry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private var imdbAttribution: some View {
        HStack(spacing: 3) {
            Link("Information courtesy of IMDb", destination: URL(string: "https://www.imdb.com")!)
            Text("(https://www.imdb.com). Used with permission.")
        }
        .font(.denbox(size: 9))
        .foregroundStyle(Color.secondaryText.opacity(0.85))
    }
}

private struct ReleaseCalendarPage: View {
    @EnvironmentObject private var model: LibraryModel
    @StateObject private var feeds = DiscoveryFeedsModel()
    @State private var monthAnchor = Date()
    @State private var selectedDate = Date()
    private let weekdayKeys = ["Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    private var persianCalendar: Calendar {
        var value = Calendar(identifier: .persian)
        value.locale = Locale(identifier: "fa_IR")
        value.timeZone = .current
        value.firstWeekday = 7
        return value
    }

    private var monthEnd: Date {
        let dayCount = persianCalendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        return persianCalendar.date(byAdding: .day, value: dayCount - 1, to: monthStart) ?? monthStart
    }

    private var apiReleaseMonths: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return [monthStart, monthEnd].reduce(into: [String]()) { result, date in
            let components = calendar.dateComponents([.year, .month], from: date)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            if !result.contains(key) { result.append(key) }
        }
    }

    private var persianMonthKey: String {
        let components = persianCalendar.dateComponents([.year, .month], from: monthAnchor)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private var monthStart: Date {
        let components = persianCalendar.dateComponents([.era, .year, .month], from: monthAnchor)
        return persianCalendar.date(from: components) ?? monthAnchor
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = persianCalendar
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.timeZone = .current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: monthStart)
    }

    private var selectedDateTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = persianCalendar
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE، d MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    private var monthCells: [Date?] {
        let days = persianCalendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekday = persianCalendar.component(.weekday, from: monthStart)
        let blankCount = (weekday - persianCalendar.firstWeekday + 7) % 7
        let blanks = Array<Date?>(repeating: nil, count: blankCount)
        let dates: [Date?] = (1...days).map { day in
            persianCalendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
        return blanks + dates
    }

    private var eventsForSelectedDate: [DiscoveryCalendarEvent] {
        feeds.releaseEvents.filter { persianCalendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Release Schedule")
                        .font(.denbox(size: 21, weight: .bold))
                    Text("Movie release dates and known TV episode air dates in the Persian calendar.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Button("Today") { setMonth(to: Date()) }
                    .buttonStyle(.bordered)
                Button {
                    Task { await reloadCalendar() }
                } label: {
                    Label("Refresh calendar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(feeds.isLoadingCalendar)
            }

            HStack {
                Button {
                    shiftMonth(-1)
                } label: {
                    Label("Previous month", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Previous month")
                Text(monthTitle)
                    .font(.denbox(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                Button {
                    shiftMonth(1)
                } label: {
                    Label("Next month", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Next month")
            }

            LazyVGrid(columns: calendarColumns, spacing: 7) {
                ForEach(weekdayKeys, id: \.self) { day in
                    Text(DenboxLanguage.localizedMessage(day))
                        .font(.denbox(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 20)
                }
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        calendarDayButton(date)
                    } else {
                        Color.clear.frame(height: 55)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))

            HStack(spacing: 14) {
                Label("Movie release", systemImage: "film")
                    .foregroundStyle(Color.orange)
                Label("TV episode", systemImage: "tv")
                    .foregroundStyle(Color.cyan)
            }
            .font(.denbox(size: 10))

            HStack {
                Text(selectedDateTitle)
                    .font(.denbox(size: 17, weight: .semibold))
                Spacer()
                if !eventsForSelectedDate.isEmpty {
                    Text(DenboxLanguage.localizedMessage("\(eventsForSelectedDate.count) events"))
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                }
            }

            if feeds.isLoadingCalendar && feeds.releaseEvents.isEmpty {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Loading release schedule…")
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else if !feeds.calendarMessages.isEmpty {
                Text(feeds.calendarMessages.map { DenboxLanguage.localizedMessage($0) }.joined(separator: " "))
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.9))
            }

            if eventsForSelectedDate.isEmpty {
                Text("No movie releases or scheduled TV episodes for this day.")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(eventsForSelectedDate) { event in
                        Button {
                            Task { await model.openCatalogTitle(matching: event.title) }
                        } label: {
                            calendarEventRow(event)
                        }
                        .buttonStyle(.plain)
                        .help("Find this title in the Simba catalog")
                    }
                }
            }

            Text("Movie dates: Box Office Mojo (US theatrical releases). Series episodes and usual airing days: TVmaze (CC BY-SA). TV schedules depend on the information supplied by each broadcaster and platform.")
                .font(.denbox(size: 9))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
        }
        .task(id: persianMonthKey) {
            await feeds.loadCalendar(cacheKey: persianMonthKey, startDate: monthStart, endDate: monthEnd,
                                     releaseMonths: apiReleaseMonths)
        }
    }

    private func calendarDayButton(_ date: Date) -> some View {
        let dayEvents = feeds.releaseEvents.filter { persianCalendar.isDate($0.date, inSameDayAs: date) }
        let isSelected = persianCalendar.isDate(date, inSameDayAs: selectedDate)
        return Button { selectedDate = date } label: {
            VStack(spacing: 4) {
                Text(persianDayNumber(date))
                    .font(.denbox(size: 12, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : Color.secondaryText)
                HStack(spacing: 3) {
                    if dayEvents.contains(where: { $0.kind == .movieRelease }) {
                        Circle().fill(Color.orange).frame(width: 4, height: 4)
                    }
                    if dayEvents.contains(where: { $0.kind == .episode }) {
                        Circle().fill(Color.cyan).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isSelected ? Color.white.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func calendarEventRow(_ event: DiscoveryCalendarEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind == .episode ? "tv" : "film")
                .font(.denbox(size: 16))
                .foregroundStyle(event.kind == .episode ? Color.cyan : Color.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.title)
                    .font(.denbox(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if event.kind == .episode {
                    HStack(spacing: 6) {
                        if let season = event.season, let number = event.episode {
                            Text(String(format: "S%02dE%02d", season, number))
                                .font(.denbox(size: 10, weight: .medium))
                                .foregroundStyle(Color.secondaryText)
                        }
                        if let episodeTitle = event.episodeTitle, !episodeTitle.isEmpty {
                            Text(episodeTitle)
                                .font(.denbox(size: 10))
                                .foregroundStyle(Color.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    let details = [
                        event.airingDays.map { DenboxLanguage.localizedMessage($0) }.joined(separator: " · "),
                        event.airtime,
                        event.channel,
                        event.timeZone
                    ].compactMap { $0 }.filter { !$0.isEmpty }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.denbox(size: 9))
                            .foregroundStyle(Color.secondaryText.opacity(0.9))
                            .lineLimit(1)
                    }
                } else {
                    Text("US theatrical release")
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(.denbox(size: 10, weight: .medium))
                .foregroundStyle(Color.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private func shiftMonth(_ amount: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        monthAnchor = calendar.date(byAdding: .month, value: amount, to: monthAnchor) ?? monthAnchor
        selectedDate = monthAnchor
    }

    private func persianDayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = persianCalendar
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.timeZone = .current
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func setMonth(to date: Date) {
        monthAnchor = date
        selectedDate = date
    }

    private func reloadCalendar() async {
        await feeds.loadCalendar(cacheKey: persianMonthKey, startDate: monthStart, endDate: monthEnd,
                                 releaseMonths: apiReleaseMonths, force: true)
    }
}

private struct IMDbTitleCard: View {
    @EnvironmentObject private var model: LibraryModel
    let metadata: IMDbTitleMetadata
    var rank: Int? = nil
    var width: CGFloat = 150
    var artworkHeight: CGFloat = 205
    var fallbackArtworkURL: URL? = nil
    @State private var artworkData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: Palette.colors((metadata.votes ?? 0) % 8), startPoint: .topLeading, endPoint: .bottomTrailing))
                if let artworkData, let image = NSImage(data: artworkData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: artworkHeight)
                        .clipped()
                } else if let fallbackArtworkURL {
                    AsyncImage(url: fallbackArtworkURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: width, height: artworkHeight)
                    .clipped()
                } else {
                    Image(systemName: metadata.kind == "Series" ? "tv" : "film")
                        .font(.denbox(size: 35, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: width, height: artworkHeight)
                }
                LinearGradient(colors: [.black.opacity(0.22), .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                if let rank {
                    Text("#\(rank)")
                        .font(.denbox(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(8)
                }
                if model.resolvingSimilarTitleID == metadata.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: width, height: artworkHeight)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(metadata.title)
                .font(.denbox(size: 12, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(.white)
            Text([metadata.year.map(String.init), metadata.rating.map { "★ \(String(format: "%.1f", $0))" }, voteLabel]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.denbox(size: 9))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .task(id: metadata.id) {
            artworkData = await model.loadIMDbArtwork(for: metadata)
        }
    }

    private var voteLabel: String? {
        guard let votes = metadata.votes else { return nil }
        return DenboxLanguage.localizedMessage("\(votes.formatted(.number.notation(.compactName))) votes")
    }
}

private struct MediaGrid: View {
    let items: [MediaItem]
    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 18, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(items) { item in
                GridPoster(item: item)
            }
        }
    }
}

private struct GridPoster: View {
    @EnvironmentObject private var model: LibraryModel
    let item: MediaItem
    var body: some View {
        Button { model.selectedItem = item } label: {
            PosterCard(item: item, personalRating: model.personalRatings[item.id]?.rating)
        }
            .buttonStyle(.plain)
    }
}

private struct EmptyLibraryState: View {
    @EnvironmentObject private var model: LibraryModel
    let isWatchlist: Bool
    let isMyRatings: Bool
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: isWatchlist ? "bookmark" : (isMyRatings ? "star" : (model.searchText.isEmpty ? "film" : "magnifyingglass")))
                .font(.denbox(size: 31, weight: .light))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(LocalizedStringKey(emptyTitle))
                .font(.denbox(size: 19, weight: .semibold))
            Text(LocalizedStringKey(emptyMessage))
                .font(.denbox(size: 12))
                .foregroundStyle(Color.secondaryText)
            if !isWatchlist && model.searchText.isEmpty {
                HStack(spacing: 10) {
                    Button("Refresh catalog", systemImage: "arrow.clockwise") {
                        Task { await model.refreshCatalog() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(model.isConnecting)

                    Button("Settings", systemImage: "gearshape") { model.showingSettings = true }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 3)
            } else if !isWatchlist {
                Button("Clear search", systemImage: "xmark") { model.searchText = "" }
                    .buttonStyle(.bordered)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 92)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
    }

    private var emptyTitle: String {
        if isWatchlist { return "Your list is ready" }
        if isMyRatings { return "No personal ratings yet" }
        if !model.searchText.isEmpty { return "No matches found" }
        if model.items.isEmpty { return "Your catalog is empty" }
        return "No titles in this section"
    }

    private var emptyMessage: String {
        if isWatchlist { return "Save a movie or show to keep it close." }
        if isMyRatings { return "Rate a movie or show from its details page to build this list." }
        if !model.searchText.isEmpty { return "Try a different title or clear your search." }
        if model.items.isEmpty { return "Refresh the API catalog or add your keys in Settings." }
        return "There are no movies or shows in this section yet."
    }
}

private struct CatalogPaginationFooter: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isLoadingMore {
                ProgressView().controlSize(.small)
                Text("Loading more titles…")
                    .font(.denbox(size: 12))
                    .foregroundStyle(Color.secondaryText)
            } else {
                Button("Load more titles", systemImage: "arrow.down.circle") {
                    model.loadMoreCatalog()
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

private struct DownloadsView: View {
    @EnvironmentObject private var model: LibraryModel
    @EnvironmentObject private var manager: DownloadManager

    var body: some View {
        if manager.entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.denbox(size: 31, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.48))
                Text("Nothing downloaded yet")
                    .font(.denbox(size: 19, weight: .semibold))
                Text("Downloads from movie and episode pages will appear here.")
                    .font(.denbox(size: 12))
                    .foregroundStyle(Color.secondaryText)
                Button("Open a local video", systemImage: "play.rectangle") { model.openLocalVideo() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 88)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
        } else {
            LazyVStack(spacing: 10) {
                ForEach(manager.entries) { entry in
                    DownloadRow(entry: entry)
                }
            }
        }
    }
}

private struct DownloadRow: View {
    @EnvironmentObject private var model: LibraryModel
    @EnvironmentObject private var manager: DownloadManager
    @ObservedObject var entry: DownloadEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.status == .completed ? "checkmark.circle.fill" : "film")
                .font(.denbox(size: 22))
                .foregroundStyle(entry.status == .failed ? Color.orange : Color.white.opacity(0.75))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .font(.denbox(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !entry.sourceTitle.isEmpty {
                        Text(entry.sourceTitle)
                            .font(.denbox(size: 9, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    statusLabel
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                    if entry.status == .downloading {
                        if entry.totalBytes == nil {
                            ProgressView().controlSize(.small)
                        } else {
                            ProgressView(value: entry.progress).frame(maxWidth: 170)
                        }
                        if let totalSegments = entry.totalSegments, totalSegments > 1 {
                            HStack(spacing: 2) {
                                ForEach(0..<min(totalSegments, 8), id: \.self) { index in
                                    Capsule()
                                        .fill(index < entry.completedSegments ? Color.white : Color.white.opacity(0.18))
                                        .frame(width: 8, height: 6)
                                }
                            }
                            .accessibilityLabel("\(entry.completedSegments) of \(totalSegments) parts complete")
                        }
                        Text(byteCount(entry.downloadedBytes, total: entry.totalBytes))
                            .font(.denbox(size: 10))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                if let error = entry.errorMessage {
                    Text(error).font(.denbox(size: 10)).foregroundStyle(Color.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var controls: some View {
        switch entry.status {
        case .queued, .downloading:
            Button("Stop", systemImage: "stop.fill") { manager.cancel(entry) }
                .labelStyle(.iconOnly)
                .help("Stop download")
        case .failed, .cancelled:
            Button("Retry", systemImage: "arrow.clockwise") { manager.retry(entry) }
                .labelStyle(.iconOnly)
                .help("Retry download")
                .disabled(entry.task != nil)
        case .completed:
            HStack(spacing: 4) {
                if let fileURL = entry.fileURL {
                    Button("Play", systemImage: "play.fill") {
                        model.playLocalVideo(fileURL, title: entry.title)
                    }
                    .labelStyle(.iconOnly)
                    .help("Play downloaded video")
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                    .labelStyle(.iconOnly)
                    .help("Show file in Finder")
                }
                Button("Remove", systemImage: "trash") { manager.remove(entry) }
                    .labelStyle(.iconOnly)
                    .help("Remove from this list")
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch entry.status {
        case .completed:
            if let totalSegments = entry.totalSegments, totalSegments > 1 {
                Text("Downloaded in \(totalSegments) parts · \(byteCount(entry.downloadedBytes, total: nil))")
            } else {
                Text("Downloaded · \(byteCount(entry.downloadedBytes, total: nil))")
            }
        case .failed: Text("Download failed")
        case .cancelled: Text("Cancelled")
        case .queued: Text("Waiting in queue")
        case .downloading:
            if let totalSegments = entry.totalSegments, totalSegments > 1 {
                Text("Downloading · \(entry.completedSegments)/\(totalSegments) parts")
            } else if entry.totalSegments == 1 {
                Text("Downloading · single part")
            } else {
                Text("Checking server for range support…")
            }
        }
    }

    private func byteCount(_ value: Int64, total: Int64?) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let current = formatter.string(fromByteCount: value)
        guard let total else { return current }
        return "\(current) / \(formatter.string(fromByteCount: total))"
    }
}

private struct MediaDetailPage: View {
    @EnvironmentObject private var model: LibraryModel
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    @State private var details: MediaDetails?
    @State private var personalRating: Int?
    @State private var referenceMetadata: ReferenceTitleMetadata?
    @State private var selectedSeasonID: String?
    @State private var selectedEpisodeID: String?
    @State private var selectedSourceID: String?
    @State private var selectedSourceTitle: String?
    @State private var isLoadingDetails = false
    @State private var isRefreshingActionLinks = false
    @State private var didLoadDetails = false
    @State private var detailsError: String?
    @State private var actionMessage: String?
    @State private var filimoMetadata: PublicTitleMetadata?
    @State private var hexDLMetadata: PublicTitleMetadata?
    @State private var savedPersianTitle: String?
    @State private var publicArtworkImage: NSImage?
    @State private var publicArtworkResolved = false
    @State private var publicArtworkAspectRatio: CGFloat = 1600.0 / 352.0

    var body: some View {
        ScrollViewReader { episodeProxy in
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 25) {
                hero

                VStack(alignment: .leading, spacing: 14) {
                    Text([DenboxLanguage.localizedMediaKind(item.kind),
                          displayedYear,
                          displayedRuntime,
                          displayedRating]
                        .compactMap { $0?.nilIfEmpty }
                        .joined(separator: "  ·  "))
                        .font(.denbox(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondaryText)

                    Text(DenboxLanguage.localizedMessage(displayedSynopsis.nilIfEmpty ?? "No description is available for this title."))
                        .font(.denbox(size: 14))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if !displayedGenres.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(displayedGenres, id: \.self) { genre in
                                Button {
                                    model.browseGenre(genre, kind: item.kind)
                                } label: {
                                    Text(IMDbGenreLocalization.displayName(for: genre))
                                        .font(.denbox(size: 11, weight: .medium))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.09), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .help(DenboxLanguage.localizedMessage("Browse titles in \(genre)"))
                            }
                        }
                    }

                    metadataLine("Director", value: details?.director ?? publicMetadataSources.compactMap(\.director).first)
                    metadataLine("Country", value: details?.country ?? publicMetadataSources.compactMap(\.country).first)
                    castSection
                    if (details?.hasSupplementalMetadata ?? false) || hasPublicSupplementalMetadata {
                        supplementalMetadata(details)
                    }
                    if let citations = referenceMetadata?.citations, !citations.isEmpty {
                        HStack(spacing: 8) {
                            Text("Automatically enriched from")
                                .foregroundStyle(Color.secondaryText)
                            ForEach(citations) { citation in
                                Link(citation.provider, destination: citation.url)
                            }
                        }
                        .font(.denbox(size: 9))
                    }
                    if details?.imdbID != nil {
                        imdbAttribution
                    }
                }
                .padding(.horizontal, 36)

                personalRatingSection

                if item.kind == "Series" {
                    seriesEpisodes
                    similarSeries
                }

                if isLoadingDetails {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Loading title details from the media API…")
                            .font(.denbox(size: 12))
                            .foregroundStyle(Color.secondaryText)
                    }
                    .padding(.horizontal, 36)
                } else if let detailsError {
                    Text(DenboxLanguage.localizedMessage(detailsError))
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .padding(.horizontal, 36)
                }
            }
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: selectedEpisodeID) { episodeID in
            guard let episodeID else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    episodeProxy.scrollTo("episode-row-\(episodeID)", anchor: .center)
                }
            }
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .onChange(of: selectedSeasonID) { _ in
            let seasonEpisodes = selectedSeason?.episodes ?? []
            if !seasonEpisodes.contains(where: { $0.id == selectedEpisodeID }) {
                selectedEpisodeID = seasonEpisodes.first?.id
            }
            selectedSourceID = nil
            selectedSourceTitle = nil
        }
        .onChange(of: model.detailsRefreshRevision) { _ in
            referenceMetadata = model.referenceMetadata(mediaID: item.id)
            filimoMetadata = model.publicTitleMetadata(mediaID: item.id, provider: .filimo)
            hexDLMetadata = model.publicTitleMetadata(mediaID: item.id, provider: .hexDL)
            savedPersianTitle = model.localizedPersianTitle(mediaID: item.id)
            Task {
                if let image = await model.cachedPublicArtwork(mediaID: item.id) {
                    updatePublicArtwork(image)
                    publicArtworkResolved = true
                }
            }
            guard let refreshed = model.recentlyRefreshedDetails[item.id] else { return }
            details = referenceMetadata.map { ReferenceMetadataService.enrich(refreshed, with: $0) } ?? refreshed
            if selectedSeasonID == nil { selectedSeasonID = details?.seasons.first?.id }
            if selectedEpisodeID == nil { selectedEpisodeID = details?.seasons.first?.episodes.first?.id }
            if selectedSourceID == nil, selectedSourceTitle == nil,
               let source = activeSources.first { selectSource(source) }
        }
        .task(id: item.id) {
            publicArtworkImage = nil
            publicArtworkResolved = false
            publicArtworkAspectRatio = 1600.0 / 352.0
            personalRating = model.personalRatings[item.id]?.rating
            filimoMetadata = model.publicTitleMetadata(mediaID: item.id, provider: .filimo)
            hexDLMetadata = model.publicTitleMetadata(mediaID: item.id, provider: .hexDL)
            referenceMetadata = model.referenceMetadata(mediaID: item.id)
            savedPersianTitle = model.localizedPersianTitle(mediaID: item.id)
            if let image = await model.cachedPublicArtwork(mediaID: item.id) {
                updatePublicArtwork(image)
                publicArtworkResolved = true
            }
            guard item.isRemote else {
                publicArtworkResolved = true
                return
            }
            async let publicMetadataRefresh = model.refreshPublicTitleMetadata(for: item)
            isLoadingDetails = true
            detailsError = nil
            if let loaded = await model.loadDetails(for: item) {
                referenceMetadata = model.referenceMetadata(mediaID: item.id)
                let resolvedDetails = referenceMetadata.map { ReferenceMetadataService.enrich(loaded, with: $0) } ?? loaded
                details = resolvedDetails
                selectedSeasonID = details?.seasons.first?.id
                selectedEpisodeID = details?.seasons.first?.episodes.first?.id
                if let source = activeSources.first { selectSource(source) }
                if let progress = model.consumePendingEpisodeProgress(for: item.id) {
                    selectEpisode(for: progress, in: resolvedDetails)
                }
                didLoadDetails = true
            } else {
                detailsError = "The title details could not be loaded. Check the connection and API settings."
                didLoadDetails = true
            }
            isLoadingDetails = false
            _ = await publicMetadataRefresh
            filimoMetadata = model.publicTitleMetadata(mediaID: item.id, provider: .filimo)
            hexDLMetadata = model.publicTitleMetadata(mediaID: item.id, provider: .hexDL)
            savedPersianTitle = model.localizedPersianTitle(mediaID: item.id)
            if let image = await model.loadPublicArtwork(mediaID: item.id) {
                updatePublicArtwork(image)
            }
            publicArtworkResolved = true
        }
    }

    private var displayedSynopsis: String {
        PersianMetadataText.preferredSynopsis(from: [
            filimoMetadata?.synopsis, hexDLMetadata?.synopsis, details?.description,
            item.synopsis, referenceMetadata?.synopsis
        ])
    }

    private var displayedPersianTitle: String? {
        publicMetadataSources.first(where: \.hasPersianTitle)?.title ?? savedPersianTitle
    }

    private var publicMetadataSources: [PublicTitleMetadata] {
        [filimoMetadata, hexDLMetadata].compactMap { $0 }
    }

    private var displayedYear: String? {
        nonEmptyPublicText(details?.year) ?? nonEmptyPublicText(item.year)
            ?? publicMetadataSources.compactMap { nonEmptyPublicText($0.year) }.first
    }

    private var displayedRuntime: String? {
        nonEmptyPublicText(details?.runtime)
            ?? publicMetadataSources.compactMap { nonEmptyPublicText($0.runtime) }.first
    }

    private var displayedGenres: [String] {
        if let genres = details?.genres, !genres.isEmpty { return genres }
        if !item.genres.isEmpty { return item.genres }
        return uniquePublicStrings(publicMetadataSources.flatMap { $0.genres ?? [] }, limit: 12)
    }

    private var hasPublicSupplementalMetadata: Bool {
        publicMetadataSources.contains { source in
            nonEmptyPublicText(source.originalTitle) != nil || nonEmptyPublicText(source.contentRating) != nil
                || source.seasonCount != nil || source.episodeCount != nil
                || nonEmptyPublicText(source.publicRating) != nil || nonEmptyPublicText(source.communityRating) != nil
                || source.crewNames?.isEmpty == false || source.publicBadges?.isEmpty == false
        }
    }

    private func nonEmptyPublicText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func uniquePublicStrings(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(values.filter { seen.insert($0).inserted }.prefix(limit))
    }

    private var displayedArtworkURL: URL? {
        if !publicArtworkResolved {
            return filimoMetadata?.posterURL ?? hexDLMetadata?.posterURL
                ?? item.artworkURL ?? referenceMetadata?.posterURL ?? details?.backdropURL
        }
        return item.artworkURL ?? referenceMetadata?.posterURL ?? details?.backdropURL
    }

    private func updatePublicArtwork(_ image: NSImage) {
        publicArtworkImage = image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cgImage.height > 0 else { return }
        let ratio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        guard ratio.isFinite, (0.35...6.0).contains(ratio) else { return }
        publicArtworkAspectRatio = ratio
    }

    private var personalRatingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your rating")
                    .font(.denbox(size: 14, weight: .semibold))
                Spacer()
                if let personalRating {
                    Text("\(personalRating) / 5")
                        .font(.denbox(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                    Button("Clear rating") {
                        self.personalRating = nil
                        model.setPersonalRating(nil, for: item)
                    }
                    .buttonStyle(.plain)
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
                }
            }
            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        personalRating = score
                        model.setPersonalRating(score, for: item)
                    } label: {
                        Image(systemName: score <= (personalRating ?? 0) ? "star.fill" : "star")
                            .font(.denbox(size: 21))
                            .foregroundStyle(score <= (personalRating ?? 0) ? Color.yellow : Color.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help(DenboxLanguage.localizedMessage("Rate \(score) out of 5 stars"))
                    .accessibilityLabel(Text(DenboxLanguage.localizedMessage("Rate \(score) out of 5 stars")))
                }
            }
            Text("Saved only on this Mac. Separate from IMDb.")
                .font(.denbox(size: 10))
                .foregroundStyle(Color.secondaryText)
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        .padding(.horizontal, 36)
    }

    private var hero: some View {
        GeometryReader { proxy in
            ZStack {
                HeroArtwork(palette: item.palette)
                if let publicArtworkImage {
                    Image(nsImage: publicArtworkImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else if let url = displayedArtworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } placeholder: {
                        Color.clear
                    }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(publicArtworkAspectRatio, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(item.kind.uppercased()))
                    .font(.denbox(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.78))
                Text(item.title)
                    .font(.denbox(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let displayedPersianTitle, displayedPersianTitle != item.title {
                    Text(displayedPersianTitle)
                        .font(.denbox(size: 23, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                }
                Text(item.subtitle)
                    .font(.denbox(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                HStack(spacing: 10) {
                    playButton
                    if let offlineURL = downloadManager.completedDownload(
                        mediaItemID: item.id,
                        episodeID: item.kind == "Series" ? selectedEpisode?.id : nil,
                        title: playbackTitle
                    ) {
                        Label("Saved offline", systemImage: "checkmark.circle.fill")
                            .font(.denbox(size: 11, weight: .medium))
                            .foregroundStyle(Color.green.opacity(0.9))
                        Button {
                            model.playLocalVideo(offlineURL, title: playbackTitle, item: item,
                                                 episode: item.kind == "Series" ? selectedEpisode : nil, details: details)
                        } label: {
                            Label("Play offline", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    downloadControl(
                        sources: item.kind == "Series"
                            ? ((selectedEpisode?.downloadSources ?? []) + (selectedEpisode?.sources ?? []))
                            : ((details?.downloadSources ?? []) + (details?.sources ?? [])),
                        title: playbackTitle,
                        label: "Download",
                        episodeID: item.kind == "Series" ? selectedEpisode?.id : nil
                    )
                    if activeSources.count > 1 {
                        Menu {
                            ForEach(activeSources) { source in
                                Button {
                                    selectSource(source)
                                } label: {
                                    if selectedSource?.id == source.id {
                                        Label(source.title, systemImage: "checkmark")
                                    } else {
                                        Text(source.title)
                                    }
                                }
                            }
                        } label: {
                            Label("Sources", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    if item.kind == "Movie" {
                        watchStatusControl(for: nil, compact: false)
                    }
                    Button { model.toggleSaved(item) } label: {
                        Label(model.savedIDs.contains(item.id) ? "In My List" : "Add to My List",
                              systemImage: model.savedIDs.contains(item.id) ? "checkmark" : "plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.top, 4)
                actionFeedback
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private var displayedRating: String? {
        if let rating = details?.imdbRating { return "IMDb ★ \(rating)" }
        if let rating = details?.rating {
            if let source = details?.ratingSource?.nilIfEmpty { return "\(source) ★ \(rating)" }
            return "★ \(rating)"
        }
        if let rating = referenceMetadata?.rating {
            return "\(referenceMetadata?.ratingSource ?? "Public source") ★ \(rating)"
        }
        if let source = publicMetadataSources.first(where: { nonEmptyPublicText($0.publicRating) != nil }),
           let rating = nonEmptyPublicText(source.publicRating) {
            return "\(source.ratingSource ?? source.provider.rawValue) ★ \(rating)"
        }
        return nil
    }

    @ViewBuilder
    private func supplementalMetadata(_ details: MediaDetails?) -> some View {
        DisclosureGroup(DenboxLanguage.localizedMessage("More details")) {
            VStack(alignment: .leading, spacing: 8) {
                metadataLine("Tagline", value: details?.tagline)
                metadataLine("Original title", value: details?.originalTitle
                            ?? publicMetadataSources.compactMap { nonEmptyPublicText($0.originalTitle) }.first)
                metadataLine("Status", value: details?.status)
                metadataLine("Content rating", value: details?.contentRating
                            ?? publicMetadataSources.compactMap { nonEmptyPublicText($0.contentRating) }.first)
                metadataLine("Original language", value: details?.originalLanguage)
                metadataLine("Seasons", value: details?.seasonCount.map(String.init)
                    ?? publicMetadataSources.compactMap(\.seasonCount).first.map(String.init))
                metadataLine("Episodes", value: details?.episodeCount.map(String.init)
                    ?? publicMetadataSources.compactMap(\.episodeCount).first.map(String.init))
                metadataLine("Networks", value: details?.networks?.joined(separator: ", "))
                metadataLine("Production companies", value: details?.productionCompanies?.joined(separator: ", "))
                metadataLine("Writers", value: details?.writers?.joined(separator: ", "))
                metadataLine("Keywords", value: details?.keywords?.joined(separator: ", "))
                if let publicRating = publicMetadataSources.first(where: { nonEmptyPublicText($0.publicRating) != nil }),
                   let score = nonEmptyPublicText(publicRating.publicRating) {
                    metadataLine("Public source rating", value: "\(publicRating.ratingSource ?? publicRating.provider.rawValue) ★ \(score)")
                }
                if let source = publicMetadataSources.first(where: { nonEmptyPublicText($0.communityRating) != nil }),
                   let score = nonEmptyPublicText(source.communityRating) {
                    metadataLine("Site rating", value: "\(source.provider.rawValue) ★ \(score)")
                }
                if let source = publicMetadataSources.first(where: { nonEmptyPublicText($0.communityVotes) != nil }),
                   let votes = nonEmptyPublicText(source.communityVotes) {
                    metadataLine("Site votes", value: "\(source.provider.rawValue) · \(votes)")
                }
                metadataLine("Public labels", value: publicMetadataSources.flatMap { $0.publicBadges ?? [] }
                    .reduce(into: [String]()) { values, value in if !values.contains(value) { values.append(value) } }
                    .joined(separator: ", "))
                metadataLine("Additional credits", value: uniquePublicStrings(publicMetadataSources.flatMap { $0.crewNames ?? [] }, limit: 30).joined(separator: ", "))
                HStack(spacing: 12) {
                    if let url = details?.trailerURL {
                        Link(DenboxLanguage.localizedMessage("Watch trailer"), destination: url)
                    }
                    if let url = details?.homepageURL {
                        Link(DenboxLanguage.localizedMessage("Official site"), destination: url)
                    }
                }
                .font(.denbox(size: 11, weight: .medium))
            }
            .padding(.top, 8)
        }
        .font(.denbox(size: 12, weight: .medium))
        .tint(Color.secondaryText)
    }

    private var castNames: [String] {
        let sourceCast: [String]
        if let cast = details?.cast, !cast.isEmpty {
            sourceCast = cast
        } else if let tvmazeCast = referenceMetadata?.castProfiles?.map(\.name), !tvmazeCast.isEmpty {
            sourceCast = tvmazeCast
        } else {
            sourceCast = publicMetadataSources.flatMap { $0.castNames ?? [] }
        }
        var seen = Set<String>()
        return sourceCast.filter { name in
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    @ViewBuilder
    private var castSection: some View {
        if !castNames.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cast")
                    .font(.denbox(size: 12))
                    .foregroundStyle(Color.secondaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 11) {
                        ForEach(castNames, id: \.self) { name in
                            let profile = referenceMetadata?.castProfiles?.first(where: {
                                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                            })
                            Button {
                                if let person = details?.castPeople.first(where: {
                                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                                }) {
                                    model.openIMDbPerson(person, imageURL: profile?.imageURL)
                                } else {
                                    model.openIMDbPerson(named: name, imdbID: profile?.imdbID, imageURL: profile?.imageURL)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    if let imageURL = profile?.imageURL {
                                        AsyncImage(url: imageURL) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFill()
                                            } else {
                                                castPortraitPlaceholder
                                            }
                                        }
                                        .frame(width: 54, height: 54)
                                        .clipShape(Circle())
                                    } else {
                                        castPortraitPlaceholder
                                            .frame(width: 54, height: 54)
                                            .clipShape(Circle())
                                    }
                                    Text(name)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let character = profile?.character, !character.isEmpty {
                                        Text(character)
                                            .lineLimit(1)
                                            .font(.denbox(size: 9))
                                            .foregroundStyle(Color.secondaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .font(.denbox(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(10)
                                .frame(width: 112, height: 120, alignment: .topLeading)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .help(DenboxLanguage.localizedMessage("Open \(name) filmography"))
                        }
                    }
                }
            }
        }
    }

    private var castPortraitPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.white.opacity(0.6))
            .padding(8)
            .frame(width: 54, height: 54)
            .background(Color.white.opacity(0.1), in: Circle())
    }

    private var imdbAttribution: some View {
        HStack(spacing: 3) {
            Link("Information courtesy of IMDb", destination: URL(string: "https://www.imdb.com")!)
            Text("(https://www.imdb.com). Used with permission.")
        }
        .font(.denbox(size: 9))
        .foregroundStyle(Color.secondaryText.opacity(0.85))
    }

    @ViewBuilder
    private var similarSeries: some View {
        if let details, !details.similarSeries.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Similar by IMDb genres")
                        .font(.denbox(size: 21, weight: .bold))
                    Text("Genre overlap from the IMDb dataset; these are not official IMDb recommendations.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(details.similarSeries) { suggestion in
                            Button {
                                Task { await model.openCatalogTitle(matching: suggestion) }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    similarCard(suggestion)
                                    if model.resolvingSimilarTitleID == suggestion.id {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                            .padding(8)
                                    } else {
                                        Image(systemName: "play.circle.fill")
                                            .font(.denbox(size: 17))
                                            .foregroundStyle(.white.opacity(0.82))
                                            .padding(8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(model.resolvingSimilarTitleID != nil)
                            .help("Search the Simba catalog and open this series")
                        }
                    }
                }
                if let message = model.similarTitleSearchMessage {
                    Text(DenboxLanguage.localizedMessage(message))
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.orange.opacity(0.9))
                }
                imdbAttribution
            }
            .padding(20)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
            .padding(.horizontal, 36)
        }
    }

    private func similarCard(_ suggestion: IMDbTitleMetadata) -> some View {
        IMDbTitleCard(metadata: suggestion, width: 140, artworkHeight: 92)
    }

    @ViewBuilder
    private var playButton: some View {
        if !item.isRemote {
            Button {
                dismiss()
                model.openLocalVideo()
            } label: {
                Label("Open a local video", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        } else {
            Button {
                Task { await playSelectedTitle() }
            } label: {
                Label(isRefreshingActionLinks ? "Loading…" : "Play",
                      systemImage: isRefreshingActionLinks ? "hourglass" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(isRefreshingActionLinks || isLoadingDetails)
            .help(selectedSource?.title ?? "Refresh links and play")
        }
    }

    @ViewBuilder
    private var seriesEpisodes: some View {
        if let details, !details.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Episodes")
                            .font(.denbox(size: 22, weight: .bold))
                        Text("Choose a season and episode to play")
                            .font(.denbox(size: 12))
                            .foregroundStyle(Color.secondaryText)
                    }
                    Spacer()
                    Picker("Season", selection: $selectedSeasonID) {
                        ForEach(details.seasons) { season in
                            Text(season.title).tag(Optional(season.id))
                        }
                    }
                    .frame(width: 180)
                    Button {
                        Task { await downloadSelectedSeason() }
                    } label: {
                        Label(isRefreshingActionLinks ? "Loading…" : "Download this season",
                              systemImage: isRefreshingActionLinks ? "hourglass" : "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(isRefreshingActionLinks)
                }
                if let season = selectedSeason {
                    LazyVStack(spacing: 9) {
                        ForEach(season.episodes) { episode in
                            episodeRow(episode)
                                .id("episode-row-\(episode.id)")
                        }
                    }
                }
                actionFeedback
            }
            .padding(22)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
            .padding(.horizontal, 36)
        } else if didLoadDetails {
            Text("The API did not return any playable episodes for this series.")
                .font(.denbox(size: 12))
                .foregroundStyle(Color.secondaryText)
                .padding(.horizontal, 36)
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if isRefreshingActionLinks {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Refreshing playback and download links…")
            }
            .font(.denbox(size: 11))
            .foregroundStyle(Color.secondaryText)
        } else if let actionMessage {
            Text(DenboxLanguage.localizedMessage(actionMessage))
                .font(.denbox(size: 11))
                .foregroundStyle(actionMessage.contains("No direct") || actionMessage.contains("No active")
                                 ? Color.orange : Color.green.opacity(0.9))
                .textSelection(.enabled)
        }
    }

    private func episodeRow(_ episode: MediaEpisode) -> some View {
        let playableSources = uniqueSources(episode.sources + episode.downloadSources)
        let offlineTitle = "\(item.title) · \(episode.title)"
        let episodeIsWatched = model.isWatched(
            mediaID: item.id,
            episodeID: episode.id,
            episodeLabel: episode.episodeLabel,
            episodeTitle: episode.title
        )
        let offlineURL = downloadManager.completedDownload(
            mediaItemID: item.id,
            episodeID: episode.id,
            title: offlineTitle
        )
        return HStack(spacing: 14) {
            Button {
                selectedEpisodeID = episode.id
                selectedSourceID = nil
                selectedSourceTitle = nil
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Text(episode.episodeLabel)
                            .font(.denbox(size: 10, weight: .bold))
                            .foregroundStyle(Color.secondaryText)
                        Text(episode.title)
                            .font(.denbox(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if let duration = episode.duration {
                            Text(duration)
                                .font(.denbox(size: 10))
                                .foregroundStyle(Color.secondaryText)
                        }
                        if let rating = episode.imdbRating {
                            Label(rating, systemImage: "star.fill")
                                .font(.denbox(size: 10, weight: .medium))
                                .foregroundStyle(Color.yellow.opacity(0.9))
                                .help("IMDb episode rating")
                        }
                        if let votes = episode.imdbVotes, votes > 0 {
                            Text("\(votes.formatted(.number.notation(.compactName))) votes")
                                .font(.denbox(size: 9))
                                .foregroundStyle(Color.secondaryText)
                        }
                        if offlineURL != nil {
                            Label("Saved offline", systemImage: "checkmark.circle.fill")
                                .font(.denbox(size: 10, weight: .medium))
                                .foregroundStyle(Color.green.opacity(0.9))
                        }
                        if episodeIsWatched {
                            Label("Watched", systemImage: "checkmark.circle.fill")
                                .font(.denbox(size: 9, weight: .medium))
                                .foregroundStyle(Color.green.opacity(0.9))
                        }
                    }
                    if !episode.synopsis.isEmpty {
                        Text(episode.synopsis)
                            .font(.denbox(size: 11))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .background(selectedEpisodeID == episode.id ? Color.white.opacity(0.1) : Color.black.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 6) {
                Button {
                    Task { await playEpisode(episode) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(isRefreshingActionLinks)

                if let offlineURL {
                    Button {
                        model.playLocalVideo(offlineURL, title: offlineTitle, item: item, episode: episode, details: details)
                    } label: {
                        Label("Play offline", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

                if playableSources.count > 1 {
                    Menu {
                        ForEach(playableSources) { source in
                            Button(source.title) {
                                beginPlayback(source, title: offlineTitle, episode: episode)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 26)
                    }
                    .menuStyle(.borderlessButton)
                }
                watchStatusControl(for: episode, compact: true)
                downloadControl(
                    sources: episode.downloadSources + episode.sources,
                    title: offlineTitle,
                    label: "Download",
                    episodeID: episode.id
                )
            }
        }
    }

    @ViewBuilder
    private func watchStatusControl(for episode: MediaEpisode?, compact: Bool) -> some View {
        let watched = model.isWatched(
            mediaID: item.id,
            episodeID: episode?.id,
            episodeLabel: episode?.episodeLabel,
            episodeTitle: episode?.title
        )
        let title = watched ? "Mark as unwatched" : "Mark as watched"
        let localizedTitle = DenboxLanguage.localizedMessage(title)
        Button {
            model.setWatched(item: item, episode: episode, details: details, watched: !watched)
        } label: {
            if compact {
                Image(systemName: watched ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(width: 22, height: 22)
            } else {
                Label(localizedTitle, systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle")
            }
        }
        .buttonStyle(.bordered)
        .help(localizedTitle)
        .accessibilityLabel(Text(localizedTitle))
    }

    private var selectedSeason: MediaSeason? {
        guard let seasons = details?.seasons else { return nil }
        return seasons.first(where: { $0.id == selectedSeasonID }) ?? seasons.first
    }

    private var selectedEpisode: MediaEpisode? {
        guard let episodes = selectedSeason?.episodes else { return nil }
        return episodes.first(where: { $0.id == selectedEpisodeID }) ?? episodes.first
    }

    private var activeSources: [MediaStreamSource] {
        let sources = item.kind == "Series"
            ? ((selectedEpisode?.sources ?? []) + (selectedEpisode?.downloadSources ?? []))
            : ((details?.sources ?? []) + (details?.downloadSources ?? []))
        return uniqueSources(sources)
    }

    private func uniqueSources(_ sources: [MediaStreamSource]) -> [MediaStreamSource] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.url.absoluteString).inserted }
    }

    private func directDownloadSources(_ sources: [MediaStreamSource]) -> [MediaStreamSource] {
        uniqueSources(sources).filter {
            !["m3u8", "mpd"].contains($0.url.pathExtension.lowercased())
        }
    }

    private var selectedSource: MediaStreamSource? {
        MediaStreamSourceSelection.preferred(
            in: activeSources,
            selectedID: selectedSourceID,
            selectedTitle: selectedSourceTitle
        )
    }

    private func preferredSource(in sources: [MediaStreamSource]) -> MediaStreamSource? {
        MediaStreamSourceSelection.preferred(
            in: sources,
            selectedID: selectedSourceID,
            selectedTitle: selectedSourceTitle
        )
    }

    private func selectSource(_ source: MediaStreamSource) {
        selectedSourceID = source.id
        selectedSourceTitle = source.title
    }

    private var playbackTitle: String {
        if item.kind == "Series", let episode = selectedEpisode { return "\(item.title) · \(episode.title)" }
        return item.title
    }

    private func metadataLine(_ label: String, value: String?) -> some View {
        Group {
            if let value = value?.nilIfEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(DenboxLanguage.localizedMessage(label)).foregroundStyle(Color.secondaryText).frame(width: 66, alignment: .leading)
                    Text(value).foregroundStyle(Color.white.opacity(0.82))
                }
                .font(.denbox(size: 12))
            }
        }
    }

    private func beginPlayback(_ source: MediaStreamSource, title: String, episode: MediaEpisode? = nil) {
        actionMessage = nil
        let playbackEpisode = item.kind == "Series" ? (episode ?? selectedEpisode) : nil
        model.playRemoteSource(source, title: title, item: item, episode: playbackEpisode, details: details)
    }

    private func matchingEpisode(_ target: MediaEpisode, in details: MediaDetails) -> (season: MediaSeason, episode: MediaEpisode)? {
        let allSeasons = details.seasons
        if let found = allSeasons.lazy.compactMap({ season in
            season.episodes.first(where: { $0.id == target.id }).map { (season, $0) }
        }).first { return found }
        if let found = allSeasons.lazy.compactMap({ season in
            season.episodes.first(where: { $0.episodeLabel == target.episodeLabel })
                .map { (season, $0) }
        }).first { return found }
        return allSeasons.lazy.compactMap({ season in
            season.episodes.first(where: {
                $0.title.localizedCaseInsensitiveCompare(target.title) == .orderedSame
            }).map { (season, $0) }
        }).first
    }

    private func selectEpisode(for progress: WatchProgress, in details: MediaDetails) {
        let allSeasons = details.seasons
        var found: (season: MediaSeason, episode: MediaEpisode)?
        if let episodeID = progress.episodeID {
            for season in allSeasons {
                if let episode = season.episodes.first(where: { $0.id == episodeID }) {
                    found = (season, episode)
                    break
                }
            }
        }
        if found == nil, let episodeLabel = progress.episodeLabel {
            for season in allSeasons {
                if let episode = season.episodes.first(where: { $0.episodeLabel == episodeLabel }) {
                    found = (season, episode)
                    break
                }
            }
        }
        if found == nil, let episodeTitle = progress.episodeTitle {
            for season in allSeasons {
                if let episode = season.episodes.first(where: {
                    $0.title.localizedCaseInsensitiveCompare(episodeTitle) == .orderedSame
                }) {
                    found = (season, episode)
                    break
                }
            }
        }
        guard let found else { return }
        selectedSeasonID = found.season.id
        selectedEpisodeID = found.episode.id
        selectedSourceID = nil
        selectedSourceTitle = nil
    }

    private func refreshActionDetails() async -> MediaDetails? {
        guard item.isRemote else { return details }
        isRefreshingActionLinks = true
        defer { isRefreshingActionLinks = false }
        guard let refreshed = await model.loadDetails(for: item, forceRefresh: true) else { return details }
        referenceMetadata = model.referenceMetadata(mediaID: item.id)
        let enriched = referenceMetadata.map { ReferenceMetadataService.enrich(refreshed, with: $0) } ?? refreshed
        details = enriched
        if selectedSeasonID == nil { selectedSeasonID = enriched.seasons.first?.id }
        if selectedEpisodeID == nil { selectedEpisodeID = enriched.seasons.first?.episodes.first?.id }
        return enriched
    }

    private func playSelectedTitle() async {
        actionMessage = nil
        let previousEpisode = item.kind == "Series" ? selectedEpisode : nil
        let resolvedDetails = await refreshActionDetails() ?? details
        if let previousEpisode, let resolvedDetails,
           let match = matchingEpisode(previousEpisode, in: resolvedDetails) {
            selectedSeasonID = match.season.id
            selectedEpisodeID = match.episode.id
            let sources = uniqueSources(match.episode.sources + match.episode.downloadSources)
            guard let source = preferredSource(in: sources) else {
                actionMessage = "No active playback source was found to play this episode."
                return
            }
            beginPlayback(source, title: "\(item.title) · \(match.episode.title)", episode: match.episode)
            return
        }
        let sources = uniqueSources((resolvedDetails?.sources ?? []) + (resolvedDetails?.downloadSources ?? []))
        guard let source = preferredSource(in: sources) else {
            actionMessage = "No active playback source was found to play this title."
            return
        }
        beginPlayback(source, title: item.title)
    }

    private func playEpisode(_ episode: MediaEpisode) async {
        actionMessage = nil
        let wasSelectedEpisode = selectedEpisodeID == episode.id
        let resolvedDetails = await refreshActionDetails() ?? details
        guard let resolvedDetails, let match = matchingEpisode(episode, in: resolvedDetails) else {
            actionMessage = "This episode was not found in the refreshed season list."
            return
        }
        selectedSeasonID = match.season.id
        selectedEpisodeID = match.episode.id
        if !wasSelectedEpisode {
            selectedSourceID = nil
            selectedSourceTitle = nil
        }
        let sources = uniqueSources(match.episode.sources + match.episode.downloadSources)
        guard let source = preferredSource(in: sources) else {
            actionMessage = "No active playback source was found to play this episode."
            return
        }
        beginPlayback(source, title: "\(item.title) · \(match.episode.title)", episode: match.episode)
    }

    private func downloadSelectedSeason() async {
        actionMessage = nil
        let previousSeason = selectedSeason
        guard let resolvedDetails = await refreshActionDetails() ?? details else {
            actionMessage = "No direct download link is available for this season."
            return
        }
        let season = resolvedDetails.seasons.first(where: { $0.id == previousSeason?.id })
            ?? resolvedDetails.seasons.first(where: { $0.title == previousSeason?.title })
        guard let season else {
            actionMessage = "This season was not found in the refreshed season list."
            return
        }
        selectedSeasonID = season.id
        let summary = downloadManager.enqueueSeason(season, series: item, preferredQuality: selectedSourceTitle)
        actionMessage = String(format: "Season downloads: %d added · %d unavailable · %d already queued or downloaded",
                               summary.queued, summary.unavailable, summary.alreadyQueuedOrDownloaded)
    }

    private func enqueueDownload(source: MediaStreamSource?, sources: [MediaStreamSource], title: String, episodeID: String?) async {
        actionMessage = nil
        var resolvedTitle = title
        var resolvedEpisodeID = episodeID
        let requestedTitle = source?.title ?? selectedSourceTitle
        let current = source.map { [$0] } ?? sources
        var downloadable = directDownloadSources(current)
        if downloadable.isEmpty, item.isRemote {
            let targetEpisode = item.kind == "Series"
                ? (details?.seasons.flatMap(\.episodes).first(where: { $0.id == episodeID }) ?? selectedEpisode)
                : nil
            let refreshed = await refreshActionDetails() ?? details
            if let targetEpisode, let refreshed, let match = matchingEpisode(targetEpisode, in: refreshed) {
                selectedSeasonID = match.season.id
                selectedEpisodeID = match.episode.id
                resolvedTitle = "\(item.title) · \(match.episode.title)"
                resolvedEpisodeID = match.episode.id
                downloadable = directDownloadSources(match.episode.downloadSources + match.episode.sources)
            } else if let refreshed {
                downloadable = directDownloadSources(refreshed.downloadSources + refreshed.sources)
            }
        }
        guard let resolvedSource = MediaStreamSourceSelection.preferred(
            in: downloadable,
            selectedID: source?.id ?? selectedSourceID,
            selectedTitle: requestedTitle
        ) else {
            actionMessage = "No direct download link is available. Adaptive HLS or DASH links cannot be saved as a single video file."
            return
        }
        if downloadManager.enqueue(source: resolvedSource, title: resolvedTitle, catalogMediaID: item.id, episodeID: resolvedEpisodeID) {
            actionMessage = "Added to Downloads"
        } else {
            actionMessage = "This download is already queued or saved."
        }
    }

    @ViewBuilder
    private func downloadControl(
        sources: [MediaStreamSource],
        title: String,
        label: String,
        episodeID: String? = nil
    ) -> some View {
        let directSources = directDownloadSources(sources)
        let selectedDownloadSource = preferredSource(in: directSources)
        HStack(spacing: 3) {
            Button {
                Task {
                    await enqueueDownload(
                        source: selectedDownloadSource,
                        sources: sources,
                        title: title,
                        episodeID: episodeID
                    )
                }
            } label: {
                Label(label, systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(isRefreshingActionLinks || (!item.isRemote && selectedDownloadSource == nil))
            .help(selectedDownloadSource?.title ?? DenboxLanguage.localizedMessage("Refresh download links"))

            if directSources.count > 1 {
                Menu {
                    ForEach(directSources) { source in
                        Button {
                            selectSource(source)
                            Task { await enqueueDownload(source: source, sources: sources, title: title, episodeID: episodeID) }
                        } label: {
                            if selectedDownloadSource?.id == source.id {
                                Label(source.title, systemImage: "checkmark")
                            } else {
                                Text(source.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 23, height: 25)
                }
                .menuStyle(.borderlessButton)
                .help(DenboxLanguage.localizedMessage("Choose download quality"))
                .disabled(isRefreshingActionLinks)
            }
        }
    }
}

private struct PlayerWindowHost: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        Group {
            if let url = model.playerURL {
                LocalPlayerSheet(url: url, title: model.playerTitle, headers: model.playerHeaders)
                    .environmentObject(model)
            } else {
                Color.black
            }
        }
        .onAppear { model.isPlayerWindowOpen = true }
        .onDisappear {
            model.playerURL = nil
            model.isPlayerWindowOpen = false
        }
    }
}

private struct LocalPlayerSheet: View {
    private enum CurrentFileRemovalMode: Equatable {
        case trash
        case permanent
    }

    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = MPVPlaybackController()
    @State private var currentURL: URL
    @State private var currentTitle: String
    @State private var currentHeaders: [String: String]

    @State private var didAutoRefreshSource = false
    @State private var attemptedPlaybackSourceURLs: Set<String> = []
    @State private var isRefreshingSource = false
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0
    @AppStorage("denbox.player.subtitle.delay") private var subtitleDelaySeconds = 0.0
    @AppStorage("denbox.player.subtitle.scale") private var subtitleScale = 1.0
    @AppStorage("denbox.player.subtitle.position") private var subtitlePosition = 100.0
    @AppStorage("denbox.player.subtitle.borderSize") private var subtitleBorderSize = 3.0
    @AppStorage("denbox.player.subtitle.fontSize") private var subtitleFontSize = 55.0
    @AppStorage("denbox.player.subtitle.font") private var subtitleFont = "sans-serif"
    @AppStorage("denbox.player.subtitle.assOverride") private var subtitleASSOverride = "yes"
    @AppStorage("denbox.player.audio.device") private var audioOutputDeviceID = "auto"
    @State private var subtitleColor = Color.white
    @State private var subtitleBorderColor = Color.black
    @State private var subtitleBackgroundOpacity = 0.7
    @State private var aspectRatio = "no"
    @State private var cropAspect = "no"
    @State private var showPlayerAdjustments = false
    @State private var showFilterEditor = false
    @State private var filterKind: MPVFilterKind = .video
    @State private var filterName = ""
    @State private var filterExpression = ""
    @State private var filterEditorMessage: String?
    @State private var rotation = 0
    @State private var loopsCurrentFile = false
    @State private var playbackSpeed = 1.0
    @State private var playerWindowScale = 1.0
    @State private var controlsHidden = false
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var lastPlayerHoverLocation: CGPoint?
    @State private var showPlaylist = false
    @State private var playlistMessage: String?
    @State private var showingFileRemovalConfirmation = false
    @State private var pendingFileRemovalMode: CurrentFileRemovalMode?
    @State private var fileActionError: String?
    @State private var showPlaybackInfo = false
    @State private var showingOnlineSubtitles = false
    @State private var pictureInPictureUnavailable = false

    init(url: URL, title: String, headers: [String: String]) {
        _currentURL = State(initialValue: url)
        _currentTitle = State(initialValue: title)
        _currentHeaders = State(initialValue: headers)
    }

    var body: some View {
        playerScene
        .onAppear {
            attemptedPlaybackSourceURLs = [currentURL.absoluteString]
            scrubPosition = model.startPlaybackSession(playerKind: "Denbox Player", localURL: currentURL)
            playback.updateNowPlayingTitle(currentTitle)
            playback.onProgress = { position, duration, delta in
                model.recordPlaybackProgress(position: position, duration: duration, watchedDelta: delta)
            }
            playback.onUserActivity = { showPlayerControls() }
            playback.onToggleFullscreen = { playback.toggleFullscreen() }
            playback.onTogglePictureInPicture = { toggleSystemPictureInPicture() }
            playback.onFindOnlineSubtitles = { showingOnlineSubtitles = true }
            playback.onSetWindowScale = { scale in
                playerWindowScale = scale
                Task { @MainActor in
                    await Task.yield()
                    playback.setWindowScale(scale)
                }
            }
            playback.onScreenshotRequested = { includeSubtitles in saveScreenshot(includeSubtitles: includeSubtitles) }
            playback.onCloseRequested = { dismiss() }
            playback.onTogglePlaybackInfo = { showPlaybackInfo.toggle() }
            playback.onToggleControls = {
                controlsHideTask?.cancel()
                controlsHidden.toggle()
                NSCursor.setHiddenUntilMouseMoves(controlsHidden)
                if !controlsHidden { scheduleControlsHide() }
            }
            playback.setSubtitlePosition(subtitlePosition)
            playback.setSubtitleDelay(subtitleDelaySeconds)
            playback.setSubtitleScale(subtitleScale)
            playback.setSubtitleBorderSize(subtitleBorderSize)
            playback.setSubtitleFontSize(subtitleFontSize)
            playback.setSubtitleFont(subtitleFont)
            playback.setSubtitleASSOverride(subtitleASSOverride)
            _ = playback.setAudioDevice(audioOutputDeviceID)
            playback.play(currentURL, headers: currentHeaders, startAtSeconds: scrubPosition)
            scheduleControlsHide()
        }
        .onChange(of: model.playerRequestID) { _ in
            guard let nextURL = model.playerURL else { return }
            playback.flushWatchProgress()
            currentURL = nextURL
            currentTitle = model.playerTitle
            currentHeaders = model.playerHeaders
            didAutoRefreshSource = false
            attemptedPlaybackSourceURLs = [nextURL.absoluteString]
            isRefreshingSource = false
            isScrubbing = false
            scrubPosition = model.startPlaybackSession(
                playerKind: "Denbox Player",
                localURL: nextURL.isFileURL ? nextURL : nil
            )
            showPlayerControls()
            playback.play(nextURL, headers: currentHeaders, startAtSeconds: scrubPosition)
        }
        .onChange(of: playback.isPlaying) { isPlaying in
            if isPlaying { scheduleControlsHide() } else { showPlayerControls() }
        }
        .onChange(of: playback.isInMiniPlayerMode) { isMiniPlayer in
            if isMiniPlayer { showPlayerControls() }
            else { scheduleControlsHide() }
        }
        .onChange(of: currentTitle) { title in
            playback.updateMiniPlayerTitle(title)
            playback.updateNowPlayingTitle(title)
        }
        .onChange(of: playback.currentTimeSeconds) { value in
            if !isScrubbing { scrubPosition = value }
        }
        .onChange(of: subtitleColor) { color in
            playback.setSubtitleColor(Self.mpvColorString(color))
        }
        .onChange(of: subtitleBackgroundOpacity) { opacity in
            playback.setSubtitleBackgroundColor("0/0/0/\(min(1, max(0, opacity)))")
        }
        .onChange(of: subtitleBorderColor) { color in
            playback.setSubtitleBorderColor(Self.mpvColorString(color))
        }
        .onChange(of: subtitlePosition) { playback.setSubtitlePosition($0) }
        .onChange(of: subtitleBorderSize) { playback.setSubtitleBorderSize($0) }
        .onChange(of: subtitleFontSize) { playback.setSubtitleFontSize($0) }
        .onChange(of: subtitleFont) { playback.setSubtitleFont($0) }
        .onChange(of: subtitleASSOverride) { playback.setSubtitleASSOverride($0) }
        .onChange(of: playback.errorMessage) { error in
            guard let error,
                  error.localizedCaseInsensitiveContains("loading failed")
                    || error.localizedCaseInsensitiveContains("source could not be opened"),
                  !currentURL.isFileURL,
                  model.hasActiveRemotePlayback else { return }
            refreshPlaybackSource(forceRefresh: false)
        }
        .onDisappear {
            controlsHideTask?.cancel()
            NSCursor.setHiddenUntilMouseMoves(false)
            playback.onUserActivity = nil
            playback.onToggleFullscreen = nil
            playback.onTogglePictureInPicture = nil
            playback.onFindOnlineSubtitles = nil
            playback.onSetWindowScale = nil
            playback.onScreenshotRequested = nil
            playback.onCloseRequested = nil
            playback.onTogglePlaybackInfo = nil
            playback.onToggleControls = nil
            playback.flushWatchProgress()
            playback.stop()
            model.finishPlaybackSession(position: playback.currentTimeSeconds, duration: playback.durationSeconds)
            playback.shutdown()
        }
        .sheet(isPresented: $showingOnlineSubtitles) {
            OnlineSubtitleSearchView(
                videoURL: currentURL,
                initialQuery: currentURL.isFileURL ? currentURL.deletingPathExtension().lastPathComponent : currentTitle,
                apiKey: SecretVault.read(account: "opensubtitles-api-key") ?? ""
            ) { subtitleURL in
                playback.addSubtitleFile(subtitleURL)
            }
        }
        .onExitCommand { dismiss() }
    }

    private var playerScene: some View {
        ZStack {
            Color.black
            MPVVideoView(controller: playback)

            if playback.isMusicMode {
                VStack(spacing: 18) {
                    Image(systemName: "music.note.tv.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(currentTitle)
                        .font(.denbox(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if playback.isLoading {
                ProgressView("Loading media…")
                    .tint(.white)
                    .padding(16)
                    .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
            }

            if playback.isBuffering && !playback.isLoading {
                VStack(spacing: 8) {
                    ProgressView(value: playback.cacheBufferingPercent, total: 100)
                        .frame(width: 180)
                    Text("Buffering…")
                        .font(.denbox(size: 12, weight: .medium))
                    if playback.cacheBufferingPercent > 0 {
                        Text("\(Int(playback.cacheBufferingPercent))%")
                            .font(.denbox(size: 10))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .tint(.white)
                .padding(16)
                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = playback.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.denbox(size: 26))
                        .foregroundStyle(.orange)
                    Text("Playback failed").font(.denbox(size: 17, weight: .bold))
                    Text(DenboxLanguage.localizedMessage(error))
                        .font(.denbox(size: 12))
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                    if isRefreshingSource {
                        ProgressView("Refreshing playback link…").tint(.white)
                    }
                    Button("Refresh playback link") { refreshPlaybackSource() }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshingSource || !model.hasActiveRemotePlayback)
                    Button("Try again") {
                        playback.retry(currentURL, headers: currentHeaders)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: 460)
                .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            }

            if playback.didReachEnd {
                VStack(spacing: 10) {
                    Text("Playback finished")
                        .font(.denbox(size: 15, weight: .semibold))
                    if let nextTitle = model.nextEpisodeTitle {
                        Text(nextTitle)
                            .font(.denbox(size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Button(action: playNextEpisode) {
                            Label("Play next episode", systemImage: "forward.end.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(22)
                .frame(maxWidth: 420)
                .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            }

            if showPlaybackInfo {
                VStack(alignment: .leading, spacing: 5) {
                    Text(currentTitle).fontWeight(.semibold)
                    Text("\(Self.timeLabel(playback.currentTimeSeconds)) / \(Self.timeLabel(playback.durationSeconds ?? 0))")
                    Text("\(Int(playback.speed * 100))% · \(Int(playback.volume))%")
                    if let audio = playback.audioOptions.first(where: \.isSelected) {
                        Text(DenboxLanguage.localizedMessage(audio.displayName))
                    }
                    if let subtitle = playback.subtitleOptions.first(where: \.isSelected) {
                        Text(DenboxLanguage.localizedMessage(subtitle.displayName))
                    }
                    Text("\(playback.videoOptions.first?.displayName ?? "Video") · \(DenboxLanguage.localizedMessage("Chapters: \(playback.chapters.count)"))")
                }
                .font(.denbox(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .padding(12)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            LinearGradient(
                colors: [controlsHidden ? .clear : .black.opacity(0.65), .clear, .clear,
                         controlsHidden ? .clear : .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if playback.isInMiniPlayerMode {
                miniPlayerTopBar.opacity(controlsHidden ? 0 : 1).allowsHitTesting(!controlsHidden)
            } else {
                topBar.opacity(controlsHidden ? 0 : 1).allowsHitTesting(!controlsHidden)
            }
        }
        .overlay(alignment: .bottom) {
            if playback.isInMiniPlayerMode {
                miniPlayerControls.opacity(controlsHidden ? 0 : 1).allowsHitTesting(!controlsHidden)
            } else {
                controlsBar.opacity(controlsHidden ? 0 : 1).allowsHitTesting(!controlsHidden)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controlsHidden)
        .animation(.easeInOut(duration: 0.22), value: playback.isInMiniPlayerMode)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let moved = PlayerControlsAutoHidePolicy.pointerMoved(
                    from: lastPlayerHoverLocation,
                    to: location
                )
                lastPlayerHoverLocation = location
                if moved { showPlayerControls() }
            case .ended:
                lastPlayerHoverLocation = nil
            }
        }
        .confirmationDialog("Confirm file action", isPresented: $showingFileRemovalConfirmation,
                            titleVisibility: .visible) {
            Button(pendingFileRemovalMode == .permanent ? "Delete Permanently" : "Move to Trash",
                   role: .destructive) {
                removeCurrentFile(permanently: pendingFileRemovalMode == .permanent)
                pendingFileRemovalMode = nil
            }
            Button("Cancel", role: .cancel) { pendingFileRemovalMode = nil }
        } message: {
            Text(currentURL.lastPathComponent)
        }
        .alert("File action failed", isPresented: Binding(
            get: { fileActionError != nil },
            set: { if !$0 { fileActionError = nil } }
        )) {
            Button("OK", role: .cancel) { fileActionError = nil }
        } message: {
            Text(DenboxLanguage.localizedMessage(fileActionError ?? ""))
        }
        .frame(
            minWidth: playback.isInMiniPlayerMode ? 420 : CGFloat(1024 * playerWindowScale),
            minHeight: playback.isInMiniPlayerMode ? 280 : CGFloat(640 * playerWindowScale)
        )
        .background(.black)
        .preferredColorScheme(.dark)
    }

    private func showPlayerControls() {
        controlsHideTask?.cancel()
        NSCursor.setHiddenUntilMouseMoves(false)
        controlsHidden = false
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        guard PlayerControlsAutoHidePolicy.shouldHide(
            isScrubbing: isScrubbing,
            hasOpenAdjustments: showPlayerAdjustments
        ) else { return }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: PlayerControlsAutoHidePolicy.idleDelayNanoseconds)
            guard !Task.isCancelled,
                  PlayerControlsAutoHidePolicy.shouldHide(
                    isScrubbing: isScrubbing,
                    hasOpenAdjustments: showPlayerAdjustments
                  ) else { return }
            controlsHidden = true
            NSCursor.setHiddenUntilMouseMoves(playback.isPointerInsidePlayerWindow())
        }
    }

    private func playerScrubbingChanged(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            showPlayerControls()
        } else {
            playback.seek(to: scrubPosition)
            scheduleControlsHide()
        }
    }

    private func pointerEnteredControls(_ hovering: Bool) {
        if hovering { showPlayerControls() }
    }

    private func toggleSystemPictureInPicture() {
        if playback.isInSystemPictureInPictureMode {
            _ = playback.exitSystemPictureInPicture()
        } else if !playback.enterSystemPictureInPicture(title: currentTitle) {
            pictureInPictureUnavailable = true
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.denbox(size: 12, weight: .bold))
                    .frame(width: 31, height: 31)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close player")

            VStack(alignment: .leading, spacing: 3) {
                Text(currentTitle).font(.denbox(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(DenboxLanguage.localizedMessage(currentURL.isFileURL ? "Local file" : (currentURL.host ?? "Online playback")))
                    .font(.denbox(size: 11))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 20)
            ColorPicker("Subtitle color", selection: $subtitleColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30, height: 28)
                .help("Subtitle color")
            playlistControl
            Menu {
                Button("Move current file to Trash", role: .destructive) {
                    pendingFileRemovalMode = .trash
                    showingFileRemovalConfirmation = true
                }
                .disabled(!canRemoveCurrentFile)
                Button("Delete current file permanently", role: .destructive) {
                    pendingFileRemovalMode = .permanent
                    showingFileRemovalConfirmation = true
                }
                .disabled(!canRemoveCurrentFile)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(DenboxLanguage.localizedMessage("File actions"))
            trackMenu
            subtitleMenu
            aspectMenu
            filterMenu
            pictureMenu
            Button {
                rotation = (rotation + 90) % 360
                playback.setRotation(rotation)
            } label: {
                Image(systemName: "rotate.right")
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .help("Rotate video")
            Menu {
                Button(playback.isInSystemPictureInPictureMode ? "Close Picture in Picture" : "Picture in Picture") {
                    toggleSystemPictureInPicture()
                }
                Button("Open mini player") {
                    _ = playback.enterMiniPlayer(title: currentTitle)
                }
                Button(playback.isMusicMode ? "Exit Music Mode" : "Music Mode") {
                    playback.toggleMusicMode()
                }
            } label: {
                Image(systemName: "pip")
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .help(DenboxLanguage.localizedMessage("Picture in Picture"))
            .alert("Picture in Picture is unavailable", isPresented: $pictureInPictureUnavailable) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("System Picture in Picture could not be started.")
            }
            Button { playback.toggleFullscreen() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .help("Full screen")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .background(LinearGradient(colors: [.black.opacity(0.82), .clear], startPoint: .top, endPoint: .bottom))
        .onHover { pointerEnteredControls($0) }
    }

    private var miniPlayerTopBar: some View {
        HStack(spacing: 8) {
            Text(currentTitle)
                .font(.denbox(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button { playback.exitMiniPlayer() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(DenboxLanguage.localizedMessage("Return to player window"))
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(DenboxLanguage.localizedMessage("Close player"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .background(LinearGradient(colors: [.black.opacity(0.82), .clear], startPoint: .top, endPoint: .bottom))
        .onHover { pointerEnteredControls($0) }
    }

    private var miniPlayerControls: some View {
        VStack(spacing: 3) {
            HStack(spacing: 12) {
                transportButton("gobackward.10", help: "Back 10 seconds") { playback.seek(by: -10) }
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.denbox(size: 18, weight: .semibold))
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(.plain)
                .help(DenboxLanguage.localizedMessage(playback.isPlaying ? "Pause" : "Play"))
                transportButton("goforward.10", help: "Forward 10 seconds") { playback.seek(by: 10) }
                Spacer(minLength: 4)
                Text(Self.timeLabel(playback.currentTimeSeconds))
                    .font(.denbox(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 8) {
                Slider(value: $scrubPosition, in: 0...max(playback.durationSeconds ?? 1, 1)) { editing in
                    playerScrubbingChanged(editing)
                }
                .disabled(playback.durationSeconds == nil)
                Text(Self.timeLabel(playback.durationSeconds ?? 0))
                    .font(.denbox(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom))
        .onHover { pointerEnteredControls($0) }
    }

    private var controlsBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 22) {
                transportButton("gobackward.10", help: "Back 10 seconds") { playback.seek(by: -10) }
                if !playback.chapters.isEmpty {
                    transportButton("backward.end", help: "Previous chapter") { playback.moveChapter(by: -1) }
                }
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.denbox(size: 22, weight: .semibold))
                        .frame(width: 46, height: 42)
                }
                .buttonStyle(.plain)
                .help(DenboxLanguage.localizedMessage(playback.isPlaying ? "Pause" : "Play"))
                transportButton("goforward.10", help: "Forward 10 seconds") { playback.seek(by: 10) }
                if !playback.chapters.isEmpty {
                    transportButton("forward.end", help: "Next chapter") { playback.moveChapter(by: 1) }
                }

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button {
                            playbackSpeed = speed
                            playback.setSpeed(speed)
                        } label: {
                            if playbackSpeed == speed {
                                Label(DenboxLanguage.localizedMessage("\(speed.formatted(.number.precision(.fractionLength(0...2))))× Speed"), systemImage: "checkmark")
                            } else {
                                Text(DenboxLanguage.localizedMessage("\(speed.formatted(.number.precision(.fractionLength(0...2))))× Speed"))
                            }
                        }
                    }
                } label: {
                    Text("\(playbackSpeed.formatted(.number.precision(.fractionLength(0...2))))×")
                        .font(.denbox(size: 12, weight: .semibold))
                        .frame(minWidth: 42)
                }
                .menuStyle(.borderlessButton)
                .help("Playback speed")

                Button {
                    loopsCurrentFile.toggle()
                    playback.setFileLoop(loopsCurrentFile)
                } label: {
                    Image(systemName: loopsCurrentFile ? "repeat.1" : "repeat")
                        .frame(width: 30, height: 30)
                        .foregroundStyle(loopsCurrentFile ? Color.white : Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Repeat current file")

                Button { playback.markABLoop() } label: {
                    Text(playback.abLoopState == 0 ? "A–B" : (playback.abLoopState == 1 ? "A" : "B"))
                        .font(.denbox(size: 11, weight: .semibold))
                        .frame(minWidth: 30, minHeight: 30)
                        .foregroundStyle(playback.abLoopState == 0 ? Color.white.opacity(0.75) : Color.orange)
                }
                .buttonStyle(.plain)
                .help("Set or clear A-B loop points")

                if !playback.chapters.isEmpty { chapterMenu }

                Button { saveScreenshot() } label: {
                    Image(systemName: "camera")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Save frame")

                Menu {
                    Button("Save frame with subtitles") { saveScreenshot(includeSubtitles: true) }
                    Button("Save frame without subtitles") { saveScreenshot(includeSubtitles: false) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton)
                .help("More playback actions")

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button { playback.toggleMute() } label: {
                        Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(.plain)
                    .help(DenboxLanguage.localizedMessage(playback.isMuted ? "Unmute" : "Mute"))
                    Slider(value: Binding(
                        get: { playback.volume },
                        set: { playback.setVolume($0) }
                    ), in: 0...130)
                    .frame(width: 105)
                    Text("\(Int(playback.volume))%")
                        .font(.denbox(size: 10).monospacedDigit())
                        .frame(width: 32, alignment: .trailing)
                }
            }
            .foregroundStyle(.white)

            HStack(spacing: 10) {
                Text(Self.timeLabel(isScrubbing ? scrubPosition : playback.currentTimeSeconds))
                    .font(.denbox(size: 10))
                    .foregroundStyle(.white.opacity(0.78))
                Slider(value: $scrubPosition, in: 0...max(playback.durationSeconds ?? 1, 1)) { editing in
                    playerScrubbingChanged(editing)
                }
                .disabled(playback.durationSeconds == nil)
                Text(Self.timeLabel(playback.durationSeconds ?? 0))
                    .font(.denbox(size: 10))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom))
        .onHover { pointerEnteredControls($0) }
    }

    private func transportButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.denbox(size: 17, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .help(DenboxLanguage.localizedMessage(help))
    }

    private var playlistControl: some View {
        Button { showPlaylist.toggle() } label: {
            Image(systemName: "list.bullet.rectangle")
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help(DenboxLanguage.localizedMessage("Playlist"))
        .popover(isPresented: $showPlaylist, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Playlist").font(.denbox(size: 14, weight: .semibold))
                    Spacer()
                    Button { choosePlaylistFiles() } label: {
                        Label("Add videos or playlist", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Button { savePlaylistToFile() } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(playback.playlist.isEmpty)
                    .help(DenboxLanguage.localizedMessage("Save playlist"))
                    Button { playback.shufflePlaylist() } label: {
                        Image(systemName: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(playback.playlist.count < 2)
                    .help(DenboxLanguage.localizedMessage("Shuffle playlist"))
                    Button { playback.togglePlaylistLoop() } label: {
                        Image(systemName: "repeat")
                            .foregroundStyle(playback.isPlaylistLoopEnabled ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.bordered)
                    .disabled(playback.playlist.isEmpty)
                    .help(DenboxLanguage.localizedMessage(
                        playback.isPlaylistLoopEnabled ? "Stop looping playlist" : "Loop playlist"
                    ))
                    .accessibilityLabel(DenboxLanguage.localizedMessage("Loop playlist"))
                }

                if playback.playlist.isEmpty {
                    Text("The playlist is empty.")
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 70)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(playback.playlist) { entry in
                                HStack(spacing: 7) {
                                    Button { playback.playPlaylistEntry(entry.index) } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: entry.isCurrent ? "play.fill" : "film")
                                                .frame(width: 16)
                                                .foregroundStyle(entry.isCurrent ? Color.accentColor : Color.secondaryText)
                                            Text(DenboxLanguage.localizedMessage(entry.title))
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button { playback.movePlaylistEntry(from: entry.index, by: -1) } label: {
                                        Image(systemName: "chevron.up")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(entry.index == 0)
                                    .help(DenboxLanguage.localizedMessage("Move up"))
                                    Button { playback.movePlaylistEntry(from: entry.index, by: 1) } label: {
                                        Image(systemName: "chevron.down")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(entry.index == playback.playlist.count - 1)
                                    .help(DenboxLanguage.localizedMessage("Move down"))
                                    Button { playback.removePlaylistEntry(entry.index) } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(playback.playlist.count < 2)
                                    .help(DenboxLanguage.localizedMessage("Remove from playlist"))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 6)
                                .background(entry.isCurrent ? Color.white.opacity(0.09) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }

                if let playlistMessage {
                    Text(DenboxLanguage.localizedMessage(playlistMessage))
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(width: 430, height: 330)
            .onHover { if $0 { showPlayerControls() } }
        }
    }

    private func choosePlaylistFiles() {
        let panel = NSOpenPanel()
        panel.title = DenboxLanguage.localizedMessage("Add videos or playlist")
        panel.prompt = DenboxLanguage.localizedMessage("Add")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let playlistTypes = MPVPlaylistDocument.chooserExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie] + playlistTypes
        panel.begin { response in
            guard response == .OK else { return }
            DispatchQueue.main.async {
                do {
                    let urls = try MPVPlaylistDocument.urls(from: panel.urls)
                    guard !urls.isEmpty else {
                        playlistMessage = "The playlist is empty."
                        return
                    }
                    playback.appendURLsToPlaylist(urls)
                    playlistMessage = nil
                } catch {
                    playlistMessage = "Could not open playlist."
                }
            }
        }
    }

    private func savePlaylistToFile() {
        let panel = NSSavePanel()
        panel.title = DenboxLanguage.localizedMessage("Save to playlist")
        panel.prompt = DenboxLanguage.localizedMessage("Save")
        panel.nameFieldStringValue = "Playlist.m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8")].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                do {
                    try playback.savePlaylist(to: url)
                    playlistMessage = "Playlist saved."
                } catch {
                    playlistMessage = "Could not save playlist."
                }
            }
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button("Find subtitles online…") { showingOnlineSubtitles = true }
            Divider()
            Button("Open subtitles from file…") { chooseSubtitleFile() }
            Button("Open secondary subtitle from file…") { chooseSubtitleFile(asSecondary: true) }
            Button("Disable subtitles") { playback.selectSubtitle(nil) }
            Button(playback.subtitleVisibility ? "Hide subtitles" : "Show subtitles") {
                playback.toggleSubtitleVisibility()
            }
            .keyboardShortcut("v", modifiers: [])
            Divider()
            Section("Subtitle encoding") {
                ForEach(MPVSubtitleEncoding.options) { encoding in
                    Button {
                        _ = playback.setSubtitleEncoding(encoding.codepage)
                    } label: {
                        if playback.subtitleEncoding.caseInsensitiveCompare(encoding.codepage) == .orderedSame {
                            Label(DenboxLanguage.localizedMessage(encoding.title), systemImage: "checkmark")
                        } else {
                            Text(DenboxLanguage.localizedMessage(encoding.title))
                        }
                    }
                }
            }
            if !playback.subtitleOptions.isEmpty {
                Divider()
                Section("Secondary subtitles") {
                    Button("Off") { playback.selectSecondarySubtitle(nil) }
                    ForEach(playback.subtitleOptions.filter { !$0.isSelected }) { track in
                        Button {
                            playback.selectSecondarySubtitle(track)
                        } label: {
                            if track.isSecondarySelected {
                                Label(DenboxLanguage.localizedMessage(track.displayName), systemImage: "checkmark")
                            } else {
                                Text(DenboxLanguage.localizedMessage(track.displayName))
                            }
                        }
                    }
                }
                Button(playback.secondarySubtitleVisibility ? "Hide secondary subtitles" : "Show secondary subtitles") {
                    playback.toggleSecondarySubtitleVisibility()
                }
            }
            Divider()
            Button("Delay subtitles by 0.5 seconds") {
                subtitleDelaySeconds += 0.5
                playback.setSubtitleDelay(subtitleDelaySeconds)
            }
            .keyboardShortcut("x", modifiers: [])
            Button("Advance subtitles by 0.5 seconds") {
                subtitleDelaySeconds -= 0.5
                playback.setSubtitleDelay(subtitleDelaySeconds)
            }
            .keyboardShortcut("z", modifiers: [])
            Button("Reset subtitle timing") {
                subtitleDelaySeconds = 0
                playback.setSubtitleDelay(0)
            }
            .keyboardShortcut("c", modifiers: [])
            Divider()
            Button("Increase subtitle size") {
                subtitleScale = min(3, subtitleScale * 1.1)
                playback.setSubtitleScale(subtitleScale)
            }
            Button("Decrease subtitle size") {
                subtitleScale = max(0.3, subtitleScale / 1.1)
                playback.setSubtitleScale(subtitleScale)
            }
            Button("Reset subtitle size") {
                subtitleScale = 1
                playback.setSubtitleScale(1)
            }
            Divider()
            Button("Darken subtitle background") {
                subtitleBackgroundOpacity = min(1, subtitleBackgroundOpacity + 0.1)
            }
            Button("Make subtitle background more transparent") {
                subtitleBackgroundOpacity = max(0, subtitleBackgroundOpacity - 0.1)
            }
            Menu("Keyboard shortcuts") {
                Section("Subtitles") {
                    Button("Next subtitle track — J") {}.disabled(true)
                    Button("Previous subtitle track — Shift+J") {}.disabled(true)
                    Button("Show or hide subtitles — V") {}.disabled(true)
                    Button("Cycle subtitle tracks — Control+Command+S") {}.disabled(true)
                    Button("Seek subtitle — Shift+← / Shift+→") {}.disabled(true)
                    Button("Online subtitle search — Command+D") {}.disabled(true)
                }
                Section("Synchronization") {
                    Button("Subtitle sync ±0.5 s — Z / X") {}.disabled(true)
                    Button("Fine subtitle sync ±0.1 s — Option+Z / Option+X") {}.disabled(true)
                    Button("Reset subtitle sync — C") {}.disabled(true)
                    Button("Audio sync ±0.5 s — Shift+9 / Shift+0") {}.disabled(true)
                    Button("Fine audio sync ±0.1 s — Option+Shift+9 / Option+Shift+0") {}.disabled(true)
                    Button("Reset audio sync — Shift+-") {}.disabled(true)
                }
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
                .font(.denbox(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.13), in: Capsule())
        }
        .menuStyle(.borderlessButton)
    }

    private var aspectMenu: some View {
        Menu {
                ForEach(Array([("Automatic", "no"), ("16:9", "16:9"), ("4:3", "4:3"), ("2.35:1", "2.35:1")].enumerated()), id: \.offset) { _, item in
                    let (label, value) = item
                Button {
                    aspectRatio = value
                    playback.setAspectRatio(value)
                } label: {
                    if aspectRatio == value {
                        Label(DenboxLanguage.localizedMessage(label), systemImage: "checkmark")
                    } else {
                        Text(DenboxLanguage.localizedMessage(label))
                    }
                }
            }
        } label: {
            Image(systemName: "aspectratio")
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .help("Aspect ratio")
    }

    private var trackMenu: some View {
        Menu {
            if !playback.videoOptions.isEmpty {
                Section("Video") {
                    Button("Disable video") { playback.selectVideo(nil) }
                    ForEach(playback.videoOptions) { track in
                        Button {
                            playback.selectVideo(track)
                        } label: {
                            if track.isSelected {
                                Label(DenboxLanguage.localizedMessage(track.displayName), systemImage: "checkmark")
                            } else {
                                Text(DenboxLanguage.localizedMessage(track.displayName))
                            }
                        }
                    }
                }
            }
            Section("Audio") {
                Button("Open audio from file…") { chooseAudioFile() }
                if !playback.audioOptions.isEmpty {
                    ForEach(playback.audioOptions) { track in
                        Button {
                            playback.selectAudio(track)
                        } label: {
                            if track.isSelected {
                                Label(DenboxLanguage.localizedMessage(track.displayName), systemImage: "checkmark")
                            } else {
                                Text(DenboxLanguage.localizedMessage(track.displayName))
                            }
                        }
                    }
                }
                Divider()
                Button("Delay audio by 0.1 seconds") { playback.setAudioDelay(playback.audioDelaySeconds + 0.1) }
                Button("Advance audio by 0.1 seconds") { playback.setAudioDelay(playback.audioDelaySeconds - 0.1) }
                Button("Reset audio timing") { playback.setAudioDelay(0) }
            }
            Section("Audio output") {
                ForEach(playback.audioDevices) { device in
                    Button {
                        guard playback.setAudioDevice(device.id) else { return }
                        audioOutputDeviceID = device.id
                    } label: {
                        if playback.selectedAudioDeviceID == device.id {
                            Label(DenboxLanguage.localizedMessage(device.displayName), systemImage: "checkmark")
                        } else {
                            Text(DenboxLanguage.localizedMessage(device.displayName))
                        }
                    }
                }
            }
            Section("Subtitles") {
                Button("Off") { playback.selectSubtitle(nil) }
                ForEach(playback.subtitleOptions) { track in
                    Button {
                        playback.selectSubtitle(track)
                    } label: {
                        if track.isSelected {
                                Label(DenboxLanguage.localizedMessage(track.displayName), systemImage: "checkmark")
                        } else {
                                Text(DenboxLanguage.localizedMessage(track.displayName))
                        }
                    }
                }
            }
            if playback.videoOptions.isEmpty && playback.audioOptions.isEmpty && playback.subtitleOptions.isEmpty {
                Text("No alternate tracks found")
            }
        } label: {
            Label("Audio and subtitles", systemImage: "waveform")
                .font(.denbox(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.13), in: Capsule())
        }
        .menuStyle(.borderlessButton)
    }

    private var pictureMenu: some View {
        Button { showPlayerAdjustments.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help("Picture options")
        .popover(isPresented: $showPlayerAdjustments, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Picture and sound")
                        .font(.denbox(size: 15, weight: .semibold))

                    GroupBox("Crop video") {
                        Picker("Crop", selection: Binding(
                            get: { cropAspect },
                            set: {
                                cropAspect = $0
                                playback.setCropAspect($0)
                            }
                        )) {
                            Text(DenboxLanguage.localizedMessage("No crop")).tag("no")
                            Text("16:9").tag("16:9")
                            Text("4:3").tag("4:3")
                            Text("2.35:1").tag("2.35:1")
                        }
                        .pickerStyle(.segmented)
                    }

                    GroupBox("Video orientation") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Flip vertically", isOn: Binding(
                                get: { playback.isVerticallyFlipped },
                                set: { _ = playback.setVerticalFlip($0) }
                            ))
                            Toggle("Mirror horizontally", isOn: Binding(
                                get: { playback.isHorizontallyMirrored },
                                set: { _ = playback.setHorizontalMirror($0) }
                            ))
                        }
                    }

                    Toggle("Deinterlace", isOn: Binding(
                        get: { playback.isDeinterlacing },
                        set: { playback.setDeinterlacing($0) }
                    ))
                    Toggle("Hardware decoding", isOn: Binding(
                        get: { playback.hardwareDecodingEnabled },
                        set: { playback.setHardwareDecoding($0) }
                    ))

                    GroupBox("Subtitle styling") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Subtitle font", selection: $subtitleFont) {
                                Text("System").tag("sans-serif")
                                Text("Arial").tag("Arial")
                                Text("Helvetica Neue").tag("Helvetica Neue")
                                Text("Geeza Pro").tag("Geeza Pro")
                                Text("Avenir Next").tag("Avenir Next")
                            }
                            HStack(spacing: 8) {
                                Text("Font size").frame(width: 72, alignment: .leading)
                                Slider(value: $subtitleFontSize, in: 12...100, step: 1)
                                Text("\(Int(subtitleFontSize))")
                                    .monospacedDigit()
                                    .frame(width: 30, alignment: .trailing)
                            }
                            HStack(spacing: 8) {
                                Text("Position").frame(width: 72, alignment: .leading)
                                Slider(value: $subtitlePosition, in: 0...100, step: 1)
                                Text("\(Int(subtitlePosition))")
                                    .monospacedDigit()
                                    .frame(width: 30, alignment: .trailing)
                            }
                            HStack(spacing: 8) {
                                Text("Outline").frame(width: 72, alignment: .leading)
                                Slider(value: $subtitleBorderSize, in: 0...10, step: 0.5)
                                Text("\(subtitleBorderSize, specifier: "%.1f")")
                                    .monospacedDigit()
                                    .frame(width: 30, alignment: .trailing)
                            }
                            Picker("ASS subtitle styles", selection: $subtitleASSOverride) {
                                Text("Respect styles").tag("no")
                                Text("Override styles").tag("yes")
                                Text("Force all styles").tag("force")
                                Text("Scale styles").tag("scale")
                                Text("Strip styles").tag("strip")
                            }
                            HStack {
                                ColorPicker("Outline color", selection: $subtitleBorderColor, supportsOpacity: false)
                                ColorPicker("Text color", selection: $subtitleColor, supportsOpacity: false)
                            }
                            HStack(spacing: 8) {
                                Text("Subtitle background")
                                Slider(value: $subtitleBackgroundOpacity, in: 0...1)
                                Text("\(Int(subtitleBackgroundOpacity * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                        .font(.denbox(size: 11))
                    }

                    GroupBox("Video adjustments") {
                        VStack(spacing: 7) {
                            ForEach(["brightness", "contrast", "gamma", "hue", "saturation"], id: \.self) { property in
                                HStack(spacing: 8) {
                                    Text(DenboxLanguage.localizedMessage(property.capitalized))
                                        .frame(width: 76, alignment: .leading)
                                    Slider(value: videoAdjustmentBinding(property), in: -100...100)
                                    Text("\(Int(videoAdjustmentValue(property)))")
                                        .monospacedDigit()
                                        .frame(width: 30, alignment: .trailing)
                                }
                            }
                        }
                    }

                    GroupBox("Audio equalizer") {
                        VStack(spacing: 7) {
                            ForEach(Array(["31 Hz", "62 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"].enumerated()), id: \.offset) { index, label in
                                HStack(spacing: 8) {
                                    Text(label).frame(width: 50, alignment: .leading)
                                    Slider(value: Binding(
                                        get: { playback.audioEQBands[index] },
                                        set: { playback.setAudioEQBand(index, gain: $0) }
                                    ), in: -12...12)
                                    Text("\(playback.audioEQBands[index], specifier: "%+.0f") dB")
                                        .monospacedDigit()
                                        .frame(width: 48, alignment: .trailing)
                                }
                            }
                            Button("Reset audio equalizer") {
                                for index in playback.audioEQBands.indices { playback.setAudioEQBand(index, gain: 0) }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                .padding(14)
            }
            .frame(width: 390, height: 620)
        }
    }

    private var filterMenu: some View {
        Button { showFilterEditor.toggle() } label: {
            Image(systemName: "camera.filters")
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help(DenboxLanguage.localizedMessage("Audio and video filters"))
        .popover(isPresented: $showFilterEditor, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio and video filters")
                        .font(.denbox(size: 15, weight: .semibold))

                    Picker("Filter type", selection: $filterKind) {
                        ForEach(MPVFilterKind.allCases) { kind in
                            Text(DenboxLanguage.localizedMessage(kind.title)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    GroupBox("Built-in presets") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(MPVFilterPresetStore.builtIn.filter { $0.kind == filterKind }) { preset in
                                Button {
                                    filterEditorMessage = playback.addFilter(preset)
                                        ? "Filter added"
                                        : "Could not add filter. Check that the current media supports it."
                                } label: {
                                    Label(DenboxLanguage.localizedMessage(preset.name), systemImage: "plus.circle")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !playback.savedFilterPresets.isEmpty {
                        GroupBox("Saved filters") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(playback.savedFilterPresets.filter { $0.kind == filterKind }) { preset in
                                    HStack(spacing: 8) {
                                        Button {
                                            filterEditorMessage = playback.addFilter(preset)
                                                ? "Filter added"
                                                : "Could not add filter. Check that the current media supports it."
                                        } label: {
                                            Text(preset.name)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        Button(role: .destructive) {
                                            playback.deleteFilterPreset(preset)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Delete filter preset")
                                    }
                                }
                            }
                        }
                    }

                    GroupBox("Custom mpv filter") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Filter name", text: $filterName)
                            TextField("MPV filter expression", text: $filterExpression, axis: .vertical)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1...3)
                            HStack {
                                Button("Save preset") {
                                    guard playback.saveFilterPreset(name: filterName, kind: filterKind, expression: filterExpression) else {
                                        filterEditorMessage = "Enter a name and a valid filter expression."
                                        return
                                    }
                                    filterEditorMessage = "Filter preset saved"
                                }
                                .disabled(filterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                          filterExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Spacer()
                                Button("Add filter") {
                                    let preset = MPVFilterPreset(
                                        id: UUID().uuidString,
                                        name: filterName,
                                        kind: filterKind,
                                        expression: filterExpression
                                    )
                                    filterEditorMessage = playback.addFilter(preset)
                                        ? "Filter added"
                                        : "Could not add filter. Check that the current media supports it."
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(filterExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    if let filterEditorMessage {
                        Text(DenboxLanguage.localizedMessage(filterEditorMessage))
                            .font(.denbox(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Active filters") {
                        if playback.activeFilters.isEmpty {
                            Text("No filters applied")
                                .font(.denbox(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(playback.activeFilters) { filter in
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(filter.name).font(.denbox(size: 12, weight: .medium))
                                            Text(filter.expression)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                        Button(role: .destructive) {
                                            _ = playback.removeFilter(filter)
                                        } label: {
                                            Image(systemName: "xmark.circle")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Remove filter")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(14)
            }
            .frame(width: 420, height: 590)
        }
    }

    private func videoAdjustmentBinding(_ property: String) -> Binding<Double> {
        Binding(get: { videoAdjustmentValue(property) }, set: { playback.setVideoAdjustment(property, value: $0) })
    }

    private func videoAdjustmentValue(_ property: String) -> Double {
        switch property {
        case "brightness": playback.videoBrightness
        case "contrast": playback.videoContrast
        case "gamma": playback.videoGamma
        case "hue": playback.videoHue
        case "saturation": playback.videoSaturation
        default: 0
        }
    }

    private var chapterMenu: some View {
        Menu {
            ForEach(playback.chapters) { chapter in
                Button {
                    playback.selectChapter(chapter.index)
                } label: {
                    if playback.currentChapterIndex == chapter.index {
                        Label(DenboxLanguage.localizedMessage(chapter.title), systemImage: "checkmark")
                    } else {
                        Text(DenboxLanguage.localizedMessage(chapter.title))
                    }
                }
            }
        } label: {
            Image(systemName: "list.number")
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .help("Chapters")
    }

    private func chooseSubtitleFile(asSecondary: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["srt", "ass", "ssa", "vtt", "sub"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = DenboxLanguage.localizedMessage(asSecondary ? "Open secondary subtitle file" : "Open subtitle file")
        panel.prompt = DenboxLanguage.localizedMessage("Open")
        panel.begin { response in
            guard response == .OK, let fileURL = panel.url else { return }
            DispatchQueue.main.async { playback.addSubtitleFile(fileURL, asSecondary: asSecondary) }
        }
    }

    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = DenboxLanguage.localizedMessage("Open audio file")
        panel.prompt = DenboxLanguage.localizedMessage("Open")
        panel.begin { response in
            guard response == .OK, let fileURL = panel.url else { return }
            DispatchQueue.main.async { playback.addAudioFile(fileURL) }
        }
    }

    private var canRemoveCurrentFile: Bool {
        guard currentURL.isFileURL,
              let values = try? currentURL.resourceValues(forKeys: [.isRegularFileKey]) else { return false }
        return values.isRegularFile == true
    }

    private func removeCurrentFile(permanently: Bool) {
        guard canRemoveCurrentFile else {
            fileActionError = "Current file must be a local file."
            return
        }

        let removedURL = currentURL.standardizedFileURL
        playback.flushWatchProgress()
        do {
            if permanently {
                try FileManager.default.removeItem(at: removedURL)
            } else {
                try FileManager.default.trashItem(at: removedURL, resultingItemURL: nil)
            }
        } catch {
            fileActionError = permanently
                ? "Could not delete current file: \(error.localizedDescription)"
                : "Could not move current file to Trash: \(error.localizedDescription)"
            return
        }

        model.finishPlaybackSession(position: playback.currentTimeSeconds, duration: playback.durationSeconds)
        guard let next = playback.removeCurrentPlaylistEntryAndAdvance(),
              let nextURL = Self.playlistURL(from: next.filename) else {
            playback.stop()
            dismiss()
            return
        }

        currentURL = nextURL
        currentTitle = next.title
        currentHeaders = [:]
        model.playerTitle = next.title
        didAutoRefreshSource = false
        attemptedPlaybackSourceURLs = [nextURL.absoluteString]
        isRefreshingSource = false
        loopsCurrentFile = false
        playback.setFileLoop(false)
        playback.clearABLoop()
        scrubPosition = model.startPlaybackSession(
            playerKind: "Denbox Player",
            localURL: nextURL.isFileURL ? nextURL : nil
        )
        playback.setPendingResumePosition(scrubPosition)
        showPlayerControls()
    }

    private static func playlistURL(from filename: String) -> URL? {
        if let url = URL(string: filename),
           let scheme = url.scheme?.lowercased(),
           ["file", "http", "https"].contains(scheme) {
            return url
        }
        guard filename.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: filename)
    }

    private func saveScreenshot(includeSubtitles: Bool = true) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(currentTitle.replacingOccurrences(of: "/", with: "-"))-frame.png"
        panel.title = DenboxLanguage.localizedMessage("Save frame")
        panel.begin { response in
            guard response == .OK, let fileURL = panel.url else { return }
            DispatchQueue.main.async { playback.captureScreenshot(to: fileURL, includeSubtitles: includeSubtitles) }
        }
    }

    private func playNextEpisode() {
        playback.flushWatchProgress()
        model.finishPlaybackSession(position: playback.currentTimeSeconds, duration: playback.durationSeconds)
        guard model.playNextEpisode(), let nextURL = model.playerURL else { return }
        currentURL = nextURL
        currentTitle = model.playerTitle
        currentHeaders = model.playerHeaders
        didAutoRefreshSource = false
        attemptedPlaybackSourceURLs = [nextURL.absoluteString]
        isRefreshingSource = false
        loopsCurrentFile = false
        playback.setFileLoop(false)
        playback.clearABLoop()
        scrubPosition = model.startPlaybackSession(playerKind: "Denbox Player")
        playback.retry(currentURL, headers: currentHeaders, startAtSeconds: scrubPosition)
    }

    private func refreshPlaybackSource(forceRefresh: Bool = true) {
        guard !isRefreshingSource, model.hasActiveRemotePlayback else { return }
        isRefreshingSource = true
        var attempted = attemptedPlaybackSourceURLs
        attempted.insert(currentURL.absoluteString)
        Task { @MainActor in
            if forceRefresh { didAutoRefreshSource = true }
            var sources = await model.activePlaybackSources(forceRefresh: forceRefresh)
            var nextSource = PlaybackSourceFallbackPolicy.nextSource(from: sources, excluding: attempted)
            if nextSource == nil, !forceRefresh, !didAutoRefreshSource {
                didAutoRefreshSource = true
                sources = await model.activePlaybackSources(forceRefresh: true)
                nextSource = PlaybackSourceFallbackPolicy.nextSource(from: sources, excluding: attempted)
            }
            isRefreshingSource = false
            guard let source = nextSource else { return }
            attemptedPlaybackSourceURLs.insert(source.url.absoluteString)
            model.useActivePlaybackSource(source)
            currentURL = source.url
            currentHeaders = source.headers
            playback.retry(source.url, headers: source.headers, startAtSeconds: playback.currentTimeSeconds)
        }
    }

    private static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }

    private static func mpvColorString(_ color: Color) -> String {
        let value = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        return "\(value.redComponent)/\(value.greenComponent)/\(value.blueComponent)/\(value.alphaComponent)"
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DenboxLanguage.preferenceKey) private var interfaceLanguage = DenboxLanguage.defaultCode
    @AppStorage(DenboxMPVConfiguration.useInputConfigurationKey) private var useMPVInputConfiguration = false
    @AppStorage(DenboxMPVConfiguration.preferredAudioLanguagesKey) private var preferredAudioLanguages = ""
    @AppStorage(DenboxMPVConfiguration.preferredSubtitleLanguagesKey) private var preferredSubtitleLanguages = ""
    @State private var showAdvancedPlayerSettings = false
    @State private var mediaAPIKey = SecretVault.read(account: "media-api-key") ?? ""
    @State private var feedKey = SecretVault.read(account: "catalog-feed-key") ?? ""
    @State private var tmdbReadToken = SecretVault.read(account: "tmdb-read-access-token") ?? ""
    @State private var tmdbTokenStatus = ""
    @State private var openSubtitlesApiKey = SecretVault.read(account: "opensubtitles-api-key") ?? ""
    @State private var openSubtitlesKeyStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("API connection")
                        .font(.denbox(size: 25, weight: .bold))
                    Text("Direct connection · local SQLite library")
                        .font(.denbox(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Picker("Language", selection: $interfaceLanguage) {
                    Text("فارسی").tag(DenboxLanguage.persianCode)
                    Text("English").tag(DenboxLanguage.englishCode)
                }
                .pickerStyle(.segmented)
                .frame(width: 165)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Media API key", systemImage: "key.horizontal")
                    .font(.denbox(size: 13, weight: .semibold))
                SecureField("API key", text: $mediaAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                SecureField("Catalog feed key", text: $feedKey)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                Text("Values are stored in macOS Keychain. Denbox calls the catalog, search, movie and series APIs directly; the SQLite database stays on this Mac.")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        model.saveAPIKeys(mediaAPIKey: mediaAPIKey, feedKey: feedKey)
                    } label: {
                        Label(model.isConnecting ? "Loading…" : "Save keys and sync", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(model.isConnecting)
                    Spacer()
                    Text(DenboxLanguage.localizedMessage(model.connectionStatus))
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            DisclosureGroup(isExpanded: $showAdvancedPlayerSettings) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Denbox reads mpv.conf and input.conf from its own configuration folder and loads Lua/JavaScript scripts from the scripts subfolder when the player opens.")
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Use mpv input.conf key bindings", isOn: $useMPVInputConfiguration)
                        .font(.denbox(size: 11))
                    Text("Track language preferences")
                        .font(.denbox(size: 11, weight: .semibold))
                    TextField("Preferred audio track languages", text: $preferredAudioLanguages,
                              prompt: Text("Example: fa,per,fas,en,eng"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Preferred subtitle track languages", text: $preferredSubtitleLanguages,
                              prompt: Text("Example: fa,per,fas,en,eng"))
                        .textFieldStyle(.roundedBorder)
                    Text("Enter comma-separated language codes in priority order. Changes apply the next time the player opens.")
                        .font(.denbox(size: 9))
                        .foregroundStyle(Color.secondaryText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Open mpv configuration folder") {
                            _ = DenboxMPVConfiguration.reveal(DenboxMPVConfiguration.directoryURL)
                        }
                        .buttonStyle(.bordered)
                        Button("Open scripts folder") {
                            _ = DenboxMPVConfiguration.reveal(DenboxMPVConfiguration.scriptsDirectoryURL)
                        }
                        .buttonStyle(.bordered)
                        Button("Edit input.conf") {
                            _ = DenboxMPVConfiguration.openInputConfiguration()
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(DenboxMPVConfiguration.directoryURL.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.secondaryText.opacity(0.8))
                        .textSelection(.enabled)
                    Text("Close and reopen the player after installing or changing scripts and mpv.conf.")
                        .font(.denbox(size: 9))
                        .foregroundStyle(Color.secondaryText.opacity(0.8))
                }
                .padding(.top, 9)
            } label: {
                Label("Advanced player", systemImage: "slider.horizontal.3")
                    .font(.denbox(size: 13, weight: .semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 9) {
                Label("Local library", systemImage: "square.stack")
                    .font(.denbox(size: 13, weight: .semibold))
                Text("Catalog: \(model.catalogName)")
                    .font(.denbox(size: 11))
                    .foregroundStyle(Color.secondaryText)
                Button { model.importCatalog() } label: {
                    Label("Import catalog JSON…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 9) {
                Label("IMDb titles, people, and charts", systemImage: "star.leadinghalf.filled")
                    .font(.denbox(size: 13, weight: .semibold))
                Text("Download IMDb's official non-commercial datasets to this Mac. They add local search for actors, directors, and writers, with their movie and TV credits, alongside title and episode ratings, season numbering, and top-rated lists. Episode ratings match by title and then SxxExx numbering. The data is refreshed daily by IMDb but must be downloaded again here to update. IMDb's bulk files do not contain photos, biographies, or franchise membership: title posters are cached from your Simba catalog, and IMDb Franchises uses curated collections matched against the local title index. Popular Today uses TMDB’s daily feed; Box Office and Release Calendar show source data as in-app lists.")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("IMDb supplies ratings and structured people and episode data when available. TVmaze adds series artwork and cast. Denbox saves the original title, Persian title, available cover, and description locally for each movie or series you open.")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 8) {
                    Label("Optional TMDB metadata", systemImage: "sparkles")
                        .font(.denbox(size: 12, weight: .semibold))
                    Spacer()
                    Link(DenboxLanguage.localizedMessage("Get a TMDB API Read Access Token"),
                         destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                        .font(.denbox(size: 10))
                }
                Text("Optional. Denbox uses this token for matched public title details and the daily popular movies and TV lists. The token stays in macOS Keychain; viewing history and My List are never sent to TMDB.")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("TMDB API Read Access Token", text: $tmdbReadToken)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                HStack(spacing: 10) {
                    Button {
                        let token = tmdbReadToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        SecretVault.save(token, account: "tmdb-read-access-token")
                        tmdbReadToken = token
                        tmdbTokenStatus = token.isEmpty
                            ? "TMDB token removed from Keychain."
                            : "TMDB token saved in Keychain."
                        model.tmdbCredentialsDidChange(hasToken: !token.isEmpty)
                    } label: {
                        Label("Save TMDB token", systemImage: "key.horizontal")
                    }
                    .buttonStyle(.bordered)
                    Text(DenboxLanguage.localizedMessage(tmdbTokenStatus))
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: 10) {
                    if let logoURL = Bundle.main.url(forResource: "TMDB-Logo", withExtension: "png"),
                       let logo = NSImage(contentsOf: logoURL) {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 28)
                    } else {
                        Text("TMDB")
                            .font(.denbox(size: 11, weight: .bold))
                    }
                    Text("This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.")
                        .font(.denbox(size: 9))
                        .foregroundStyle(Color.secondaryText.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 8) {
                    Label("Online subtitles", systemImage: "captions.bubble")
                        .font(.denbox(size: 12, weight: .semibold))
                    Spacer()
                    Link("Get an OpenSubtitles API key",
                         destination: URL(string: "https://www.opensubtitles.com/en/consumers")!)
                        .font(.denbox(size: 10))
                }
                Text("Optional. Add your own OpenSubtitles application key to search and download subtitles from the player. Denbox stores it in macOS Keychain and sends it only to OpenSubtitles.")
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("OpenSubtitles API key", text: $openSubtitlesApiKey)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                HStack(spacing: 10) {
                    Button {
                        let key = openSubtitlesApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        SecretVault.save(key, account: "opensubtitles-api-key")
                        openSubtitlesApiKey = key
                        openSubtitlesKeyStatus = key.isEmpty
                            ? "OpenSubtitles API key removed from Keychain."
                            : "OpenSubtitles API key saved in Keychain."
                    } label: {
                        Label("Save OpenSubtitles key", systemImage: "key.horizontal")
                    }
                    .buttonStyle(.bordered)
                    Text(DenboxLanguage.localizedMessage(openSubtitlesKeyStatus))
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Button {
                    model.checkPublicReferencesForCatalog()
                } label: {
                    Label(DenboxLanguage.localizedMessage(model.isCheckingPublicReferences ? "Checking public references…" : "Check public references for loaded titles"),
                          systemImage: model.isCheckingPublicReferences ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isCheckingPublicReferences || model.items.isEmpty)
                Text(DenboxLanguage.localizedMessage(model.publicReferenceStatus))
                    .font(.denbox(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                HStack(spacing: 10) {
                    Button {
                        Task { await model.refreshIMDbDataset() }
                    } label: {
                        Label(model.isUpdatingIMDbDataset ? "Updating…" : "Download / refresh IMDb data",
                              systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isUpdatingIMDbDataset)
                    Spacer(minLength: 6)
                    Text(DenboxLanguage.localizedMessage(model.imdbDatasetStatus))
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Text("Personal, non-commercial use only. The IMDb files stay local and are not included in app releases.")
                    .font(.denbox(size: 9))
                    .foregroundStyle(Color.secondaryText.opacity(0.85))
                HStack(spacing: 3) {
                    Link("Information courtesy of IMDb", destination: URL(string: "https://www.imdb.com")!)
                    Text("(https://www.imdb.com). Used with permission.")
                }
                .font(.denbox(size: 9))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            Spacer()
            Text("Denbox for Mac · Direct API mode")
                .font(.denbox(size: 10))
                .foregroundStyle(Color.secondaryText.opacity(0.8))
        }
        .padding(25)
        .frame(width: 640, height: 810)
        .background(Color.canvas)
    }
}

private extension Color {
    static let canvas = Color(red: 0.055, green: 0.061, blue: 0.071)
    static let sidebar = Color(red: 0.085, green: 0.092, blue: 0.102)
    static let secondaryText = Color(red: 0.62, green: 0.65, blue: 0.69)
}
