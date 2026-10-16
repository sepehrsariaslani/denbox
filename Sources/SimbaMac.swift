import AppKit
import AVKit
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

    var body: some Scene {
        WindowGroup("Denbox") {
            MainWindow()
                .environmentObject(model)
                .environmentObject(model.downloadManager)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
    }
}
#endif

enum LibrarySection: String, CaseIterable, Identifiable {
    case home = "Home"
    case movies = "Movies"
    case shows = "TV Shows"
    case imdbCharts = "IMDb Charts"
    case imdbPeople = "IMDb People"
    case imdbFranchises = "IMDb Franchises"
    case watchlist = "My List"
    case downloads = "Downloads"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .movies: "film"
        case .shows: "tv"
        case .imdbCharts: "chart.bar.xaxis"
        case .imdbPeople: "person.2"
        case .imdbFranchises: "rectangle.stack"
        case .watchlist: "bookmark"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Sendable {
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
        matchingTitles: [String] = []
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
    }
}

struct MediaStreamSource: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let headers: [String: String]
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

    var hasUsefulContent: Bool {
        !sources.isEmpty || !downloadSources.isEmpty || !seasons.isEmpty
            || description?.isEmpty == false || year?.isEmpty == false
            || rating?.isEmpty == false || !genres.isEmpty || !cast.isEmpty
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

private enum MediaTitleMatching {
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
                    matchingTitles: episode.matchingTitles
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
    static func enrich(_ details: MediaDetails, for item: MediaItem) -> MediaDetails {
        guard item.kind == "Series",
              let matched = IMDbMetadataStore.shared.enrichment(
                title: item.title,
                year: details.year ?? item.year,
                includeSimilar: false
              ) else {
            return details
        }
        let seasons = IMDbEpisodeMatcher.remap(details.seasons, using: matched.episodes)
        return MediaDetails(
            description: details.description,
            year: matched.series.year.map(String.init) ?? details.year,
            rating: details.rating,
            runtime: details.runtime,
            genres: matched.series.genres.isEmpty ? details.genres : matched.series.genres,
            country: details.country,
            director: details.director,
            cast: details.cast,
            sources: details.sources,
            downloadSources: details.downloadSources,
            seasons: seasons,
            imdbID: matched.series.tconst,
            imdbRating: matched.series.rating.map { String(format: "%.1f", $0) },
            imdbVotes: matched.series.votes,
            similarSeries: []
        )
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var section: LibrarySection = .home
    @Published var searchText = ""
    @Published var savedIDs: Set<String> = []
    @Published var selectedItem: MediaItem?
    @Published var playerURL: URL?
    @Published var playerTitle = "Now Playing"
    @Published var playerHeaders: [String: String] = [:]
    @Published var showingSettings = false
    @Published var catalogName = "Local library"
    @Published private(set) var connectionStatus = "Loading local database…"
    @Published private(set) var isConnecting = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreMovies = false
    @Published private(set) var hasMoreSeries = false
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var remoteSearchResults: [MediaItem] = []
    @Published private(set) var didFinishRemoteSearch = false
    @Published private(set) var imdbDatasetStatus = "IMDb dataset is not downloaded."
    @Published private(set) var isUpdatingIMDbDataset = false
    @Published private(set) var imdbChartLists: IMDbChartLists?
    @Published private(set) var isLoadingIMDbCharts = false
    @Published private(set) var imdbPeopleAvailable = false
    @Published private(set) var resolvingSimilarTitleID: String?
    @Published private(set) var similarTitleSearchMessage: String?
    @Published private(set) var detailsRefreshRevision = 0

    let downloadManager: DownloadManager
    private let database: MediaDatabase
    private let refreshStaleDetailsInBackground: Bool
    private(set) var recentlyRefreshedDetails: [String: MediaDetails] = [:]
    private var searchTask: Task<Void, Never>?
    private var artworkLookupsInFlight: Set<String> = []
    private var imdbEnrichmentsInFlight: Set<String> = []
    private var imdbRecommendationsInFlight: Set<String> = []
    private var catalogRefreshInProgress = false
    private var detailRefreshesInFlight: Set<String> = []
    private var activeRemotePlayback: (
        item: MediaItem,
        episodeID: String?,
        episodeLabel: String?,
        episodeTitle: String?,
        sourceTitle: String?
    )?
    private var nextMoviePage = 0
    private var nextSeriesPage = 0

    init(loadRemoteCatalog: Bool = true, refreshStaleDetailsInBackground: Bool = true) {
        self.refreshStaleDetailsInBackground = refreshStaleDetailsInBackground
        let database = MediaDatabase()
        self.database = database
        self.downloadManager = DownloadManager(database: database)
        if let updated = IMDbMetadataStore.shared.lastUpdated {
            imdbDatasetStatus = "IMDb dataset ready · updated \(updated.formatted(date: .abbreviated, time: .shortened))"
        }
        imdbPeopleAvailable = IMDbMetadataStore.shared.hasPeopleData()
        let cached = database.loadCatalog()
        if !cached.isEmpty {
            items = cached
            catalogName = "Denbox Library"
            let movies = cached.filter { $0.kind == "Movie" }.count
            let series = cached.filter { $0.kind == "Series" }.count
            connectionStatus = "Local database · \(movies) movies · \(series) series"
        }
        savedIDs = database.loadSavedIDs()
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
        case .imdbCharts, .imdbPeople, .imdbFranchises:
            base = []
        case .watchlist:
            base = items.filter { savedIDs.contains($0.id) }
        case .downloads:
            base = []
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        let localMatches = base.filter { $0.title.localizedCaseInsensitiveContains(query) }
        guard didFinishRemoteSearch else { return localMatches }
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
           let payload = try? JSONSerialization.jsonObject(with: cached.payload, options: [.fragmentsAllowed]) {
            let details = Self.parseDetails(payload, for: item)
            scheduleIMDbEnrichment(for: item, details: details)
            if refreshStaleDetailsInBackground,
               Date().timeIntervalSince(cached.fetchedAt) >= 5 * 60 {
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
        var fallback: MediaDetails?
        for url in DirectMediaAPI.detailsURLs(for: item, apiKey: apiKey) {
            if let response = try? await DirectMediaAPI.getJSON(url: url, timeout: 12) {
                let details = Self.parseDetails(response, for: item)
                if details.hasUsefulContent {
                    cacheDetailsPayload(response, for: item)
                    scheduleIMDbEnrichment(for: item, details: details)
                    return details
                }
                if fallback == nil { fallback = details }
            }
        }
        if let fallback { return fallback }
        if reportFailure && !Task.isCancelled {
            connectionStatus = "Details could not be loaded. Check the API key and connection."
        }
        return nil
    }

    private func cacheDetailsPayload(_ payload: Any, for item: MediaItem) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        database.saveDetailsPayload(data, for: item.id, fetchedAt: Date())
    }

    private func scheduleIMDbEnrichment(for item: MediaItem, details: MediaDetails) {
        guard item.kind == "Series", IMDbMetadataStore.shared.isAvailable,
              imdbEnrichmentsInFlight.insert(item.id).inserted else { return }
        Task { [weak self] in
            let enriched = await Task.detached(priority: .utility) {
                IMDbMediaEnricher.enrich(details, for: item)
            }.value
            guard let self else { return }
            self.imdbEnrichmentsInFlight.remove(item.id)
            guard enriched.imdbID != nil else { return }
            self.recentlyRefreshedDetails[item.id] = enriched
            self.detailsRefreshRevision += 1
            self.scheduleIMDbRecommendations(for: item, seriesID: enriched.imdbID!)
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
                similarSeries: recommendations
            )
            self.detailsRefreshRevision += 1
        }
    }

    func playRemoteSource(_ source: MediaStreamSource, title: String, item: MediaItem, episode: MediaEpisode?) {
        activeRemotePlayback = (
            item: item,
            episodeID: episode?.id,
            episodeLabel: episode?.episodeLabel,
            episodeTitle: episode?.title,
            sourceTitle: source.title
        )
        playerTitle = title
        playerHeaders = source.headers
        playerURL = source.url
    }

    func refreshActivePlaybackSource() async -> MediaStreamSource? {
        guard let active = activeRemotePlayback,
              let details = await loadDetails(for: active.item, forceRefresh: true) else { return nil }
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

        guard !candidates.isEmpty else { return nil }
        let source = candidates.first(where: {
            $0.title.localizedCaseInsensitiveCompare(active.sourceTitle ?? "") == .orderedSame
        }) ?? candidates.first!
        activeRemotePlayback?.sourceTitle = source.title
        playerHeaders = source.headers
        playerURL = source.url
        return source
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
            let timestamp = IMDbMetadataStore.shared.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "now"
            imdbDatasetStatus = "IMDb dataset ready · updated \(timestamp)"
            imdbChartLists = nil
            imdbPeopleAvailable = IMDbMetadataStore.shared.hasPeopleData()
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
        for url in DirectMediaAPI.searchURLs(query: metadata.title, routeKey: apiKey) {
            guard let payload = try? await DirectMediaAPI.getJSON(url: url, timeout: 15) else { continue }
            let matches = Self.searchItems(from: payload, fallbackKind: metadata.kind)
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
            if let item = matches.first?.0 { return item }
        }
        return nil
    }

    private func enrichWithIMDb(_ details: MediaDetails, item: MediaItem) -> MediaDetails {
        IMDbMediaEnricher.enrich(details, for: item)
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
        remoteSearchResults = []
        didFinishRemoteSearch = false
        guard !query.isEmpty else { return }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                guard let apiKey = SecretVault.read(account: "media-api-key"),
                      let fallbackURL = DirectMediaAPI.searchFallbackURL(query: query) else {
                    throw DirectMediaAPIError.invalidURL
                }
                var payload: Any?
                for routeURL in DirectMediaAPI.searchURLs(query: query, routeKey: apiKey) {
                    if let routePayload = try? await DirectMediaAPI.getJSON(url: routeURL, timeout: 10),
                       !Self.searchItems(from: routePayload).isEmpty {
                        payload = routePayload
                        break
                    }
                }
                let resolvedPayload: Any
                if let payload {
                    resolvedPayload = payload
                } else {
                    resolvedPayload = try await DirectMediaAPI.getJSON(url: fallbackURL)
                }
                guard !Task.isCancelled else { return }
                remoteSearchResults = Self.searchItems(from: resolvedPayload)
                database.saveRemoteItems(remoteSearchResults)
                didFinishRemoteSearch = true
            } catch {
                guard !Task.isCancelled else { return }
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

        do {
            async let moviePayload = DirectMediaAPI.getJSON(url: movieURL)
            async let seriesPayload = DirectMediaAPI.getJSON(url: seriesURL)
            let (movieResponse, seriesResponse) = try await (moviePayload, seriesPayload)
            let movieRows = DirectMediaAPI.rows(from: movieResponse) ?? []
            let seriesRows = DirectMediaAPI.rows(from: seriesResponse) ?? []
            let movies = Self.mediaItems(from: movieRows, fallbackKind: "Movie", offset: 0)
            let series = Self.mediaItems(from: seriesRows, fallbackKind: "Series", offset: movies.count)
            let remoteItems = movies + series
            guard !remoteItems.isEmpty else {
                connectionStatus = "The API returned an empty catalog."
                return
            }
            database.saveRemoteItems(Self.uniqueItems(remoteItems))
            items = database.loadCatalog()
            catalogName = "Denbox API"
            nextMoviePage = 1
            nextSeriesPage = 1
            hasMoreMovies = movieRows.count >= DirectMediaAPI.pageSize
            hasMoreSeries = seriesRows.count >= DirectMediaAPI.pageSize
            let movieCount = items.filter { $0.kind == "Movie" }.count
            let seriesCount = items.filter { $0.kind == "Series" }.count
            connectionStatus = "Loaded first page · \(movieCount) movies · \(seriesCount) series"
            section = .home
        } catch {
            connectionStatus = "API unavailable. Showing the local database."
            let cached = database.loadCatalog()
            if !cached.isEmpty { items = cached }
        }
    }

    var canLoadMoreCatalog: Bool {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isLoadingMore else { return false }
        return switch section {
        case .home: hasMoreMovies || hasMoreSeries
        case .movies: hasMoreMovies
        case .shows: hasMoreSeries
        case .watchlist, .downloads, .imdbCharts, .imdbPeople, .imdbFranchises: false
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

        if loadMovies {
            if let url = DirectMediaAPI.feedURL(filter: 0, page: nextMoviePage, routeKey: feedKey),
               let response = try? await DirectMediaAPI.getJSON(url: url),
               let rows = DirectMediaAPI.rows(from: response) {
                fetched += 1
                let pageItems = Self.mediaItems(from: rows, fallbackKind: "Movie", offset: nextMoviePage * DirectMediaAPI.pageSize)
                added += appendCatalogPage(pageItems, rawCount: rows.count, kind: "Movie")
                if !rows.isEmpty { nextMoviePage += 1 }
            } else {
                failures += 1
            }
        }
        if loadSeries {
            if let url = DirectMediaAPI.feedURL(filter: 31, page: nextSeriesPage, routeKey: feedKey),
               let response = try? await DirectMediaAPI.getJSON(url: url),
               let rows = DirectMediaAPI.rows(from: response) {
                fetched += 1
                let pageItems = Self.mediaItems(from: rows, fallbackKind: "Series", offset: nextSeriesPage * DirectMediaAPI.pageSize)
                added += appendCatalogPage(pageItems, rawCount: rows.count, kind: "Series")
                if !rows.isEmpty { nextSeriesPage += 1 }
            } else {
                failures += 1
            }
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
    }

    private func appendCatalogPage(_ pageItems: [MediaItem], rawCount: Int, kind: String) -> Int {
        var known = Set(items.map(\.id))
        let newItems = pageItems.filter { known.insert($0.id).inserted }
        let reachedEnd = rawCount == 0 || rawCount < DirectMediaAPI.pageSize
        if kind == "Movie" { hasMoreMovies = !reachedEnd }
        else { hasMoreSeries = !reachedEnd }
        if !newItems.isEmpty {
            database.saveRemoteItems(newItems)
            items = database.loadCatalog()
        }
        return newItems.count
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

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func parseDetails(_ payload: Any, for item: MediaItem) -> MediaDetails {
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

    private static func detailObject(_ payload: Any, isSeries: Bool) -> [String: Any] {
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

    private static func stringList(_ value: Any?) -> [String] {
        guard let value, !(value is NSNull) else { return [] }
        if let value = string(value) { return [value] }
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            if let value = string(row) { return value }
            guard let object = row as? [String: Any] else { return nil }
            return string(object["name"]) ?? string(object["title"]) ?? string(object["title_fa"])
        }
    }

    private static func parseSeasons(from detail: [String: Any]) -> [MediaSeason] {
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
                guard !sources.isEmpty else { continue }
                let downloadSources = streamSources(from: ["sources": episode], includeDownloadFields: true)
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

    private static func streamSources(from value: Any, includeDownloadFields: Bool = false) -> [MediaStreamSource] {
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

    private static func integer(_ value: Any?) -> Int? {
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

    func playLocalVideo(_ url: URL, title: String) {
        activeRemotePlayback = nil
        playerTitle = title
        playerHeaders = [:]
        playerURL = url
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

private enum DirectMediaAPI {
    static let pageSize = 30
    private static let feedHost = "https://rubyxpin.info"
    // Current HTTPS origin advertised by the APK's config endpoint.
    private static let apkAPIBase = "https://ninwinios.info/api"
    private static let knownMediaHost = "https://gitcss.info"
    private static let searchHost = "https://gitcss.info/api-user/newapi/like.php"

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

    static func getJSON(url: URL, timeout: TimeInterval = 25) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DirectMediaAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw DirectMediaAPIError.server("HTTP \(http.statusCode)") }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private enum SecretVault {
    private static let service = "com.sepehr.SimbaMac.media-api"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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
    let fileURL: URL
    let byteCount: Int64
    let segmentCount: Int
    let createdAt: Date
    let catalogMediaID: String?
    let episodeID: String?
}

final class MediaDatabase {
    private var handle: OpaquePointer?

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
        CREATE TABLE IF NOT EXISTS downloaded_media (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL,
            byte_count INTEGER NOT NULL,
            segment_count INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            catalog_media_id TEXT,
            episode_id TEXT
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
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func loadCatalog() -> [MediaItem] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let sql = "SELECT id,api_id,title,subtitle,synopsis,year,kind,symbol,palette,artwork_url,source FROM media ORDER BY updated_at DESC,title COLLATE NOCASE"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let source = columnText(statement, 10) ?? "api"
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
                isRemote: source == "api"
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

    func loadDownloadedMedia() -> [DownloadedMedia] {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        let sql = "SELECT id,title,file_path,byte_count,segment_count,created_at,catalog_media_id,episode_id FROM downloaded_media ORDER BY created_at DESC"
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
        let sql = "INSERT OR REPLACE INTO downloaded_media(id,title,file_path,byte_count,segment_count,created_at,catalog_media_id,episode_id) VALUES(?,?,?,?,?,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(item.id, at: 1, in: statement)
        bind(item.title, at: 2, in: statement)
        bind(item.fileURL.path, at: 3, in: statement)
        sqlite3_bind_int64(statement, 4, item.byteCount)
        sqlite3_bind_int(statement, 5, Int32(item.segmentCount))
        sqlite3_bind_double(statement, 6, item.createdAt.timeIntervalSince1970)
        bind(item.catalogMediaID, at: 7, in: statement)
        bind(item.episodeID, at: 8, in: statement)
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

enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case completed = "Downloaded"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

@MainActor
final class DownloadEntry: ObservableObject, Identifiable {
    let id: String
    let title: String
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
        self.source = source
        self.catalogMediaID = catalogMediaID
        self.episodeID = episodeID
        createdAt = Date()
        status = .queued
    }

    init(completed item: DownloadedMedia) {
        id = item.id
        title = item.title
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
    @Published private(set) var entries: [DownloadEntry]
    @Published private(set) var offlineRevision = 0
    private let database: MediaDatabase
    private var activeCount = 0
    private let maximumActiveDownloads = 2

    init(database: MediaDatabase) {
        self.database = database
        entries = database.loadDownloadedMedia().map(DownloadEntry.init(completed:))
    }

    func enqueue(source: MediaStreamSource, title: String, catalogMediaID: String? = nil, episodeID: String? = nil) {
        if entries.contains(where: { $0.source?.url == source.url && ($0.status == .queued || $0.status == .downloading) }) {
            return
        }
        let entry = DownloadEntry(title: title, source: source, catalogMediaID: catalogMediaID, episodeID: episodeID)
        entries.insert(entry, at: 0)
        startNext()
    }

    func completedDownload(mediaItemID: String, episodeID: String?, title: String) -> URL? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first { entry in
            guard entry.status == .completed,
                  let fileURL = entry.fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path) else { return false }
            if entry.catalogMediaID == mediaItemID, entry.episodeID == episodeID { return true }
            return entry.catalogMediaID == nil
                && entry.title.compare(normalizedTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }?.fileURL
    }

    func cancel(_ entry: DownloadEntry) {
        guard entry.status == .queued || entry.status == .downloading else { return }
        if entry.status == .queued {
            entry.status = .cancelled
        } else {
            entry.task?.cancel()
        }
    }

    func retry(_ entry: DownloadEntry) {
        guard entry.status == .failed || entry.status == .cancelled,
              entry.source != nil else { return }
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
                fileURL: destination,
                byteCount: report.byteCount,
                segmentCount: report.segmentCount,
                createdAt: entry.createdAt,
                catalogMediaID: entry.catalogMediaID,
                episodeID: entry.episodeID
            )
            database.saveDownloadedMedia(saved)
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
    @State private var detailPath: [MediaItem] = []

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 270)
        } detail: {
            NavigationStack(path: $detailPath) {
                mainContent
                    .navigationDestination(for: MediaItem.self) { item in
                        MediaDetailPage(item: item)
                            .environmentObject(model)
                    }
            }
            .background(Color.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1020, minHeight: 700)
        .onChange(of: model.selectedItem) { item in
            guard let item else { return }
            detailPath.append(item)
            model.selectedItem = nil
        }
        .onChange(of: model.section) { _ in
            detailPath.removeAll()
        }
        .sheet(isPresented: Binding(
            get: { model.playerURL != nil },
            set: { if !$0 { model.playerURL = nil } }
        )) {
            if let url = model.playerURL {
                LocalPlayerSheet(url: url, title: model.playerTitle, headers: model.playerHeaders)
                    .environmentObject(model)
            }
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
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
                    if model.section == .imdbPeople {
                        IMDbPeoplePage()
                    } else if model.section == .imdbFranchises {
                        IMDbFranchisesPage()
                    } else if model.section == .downloads {
                        DownloadsView()
                    } else if model.section == .imdbCharts {
                        IMDbChartsPage()
                    } else if model.visibleItems.isEmpty {
                        EmptyLibraryState(isWatchlist: model.section == .watchlist)
                    } else {
                        if model.section == .home && model.searchText.isEmpty {
                            MediaShelf(title: "Featured in your library", subtitle: "A closer look at what’s available", items: Array(model.visibleItems.prefix(4)), landscape: true)
                            MediaShelf(title: "Movies", subtitle: "Stories for tonight", items: model.visibleItems.filter { $0.kind == "Movie" })
                            MediaShelf(title: "TV Shows", subtitle: "A little more to look forward to", items: model.visibleItems.filter { $0.kind == "Series" })
                        } else {
                            MediaGrid(items: model.visibleItems)
                        }
                    }
                    if model.section != .downloads && model.section != .watchlist
                        && (model.canLoadMoreCatalog || model.isLoadingMore) {
                        CatalogPaginationFooter()
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.canvas)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Text(model.section.rawValue)
                .font(.system(size: 21, weight: .semibold))
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
                Text(model.searchText.isEmpty ? model.section.rawValue : "Search results")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                Text(headingSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.top, 12)
        }
    }

    private var headingSubtitle: String {
        if !model.searchText.isEmpty { return "\(model.visibleItems.count) results · From \(model.catalogName)" }
        return switch model.section {
        case .imdbCharts: "Top rated titles, most-voted lists, and live box office"
        case .imdbPeople: "Search IMDb actors, directors, writers, and their filmographies"
        case .imdbFranchises: "Browse official IMDb franchise interests and their titles"
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
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(1.8)
                    Text("MOVIES & SERIES")
                        .font(.system(size: 8, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 28)

            Text("LIBRARY")
                .font(.system(size: 10, weight: .bold))
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
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 21)
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: model.section == item ? .semibold : .regular))
                            Spacer()
                            let count: Int? = switch item {
                            case .movies: model.items.filter { $0.kind == "Movie" }.count
                            case .shows: model.items.filter { $0.kind == "Series" }.count
                            case .watchlist: model.savedIDs.count
                            default: nil
                            }
                            if let count, count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white.opacity(0.75))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.catalogName)
                        .font(.system(size: 12, weight: .medium))
                    Text(model.connectionStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button { model.showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Catalog settings")
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.83))
                .padding(.bottom, 13)

                Text(item.title)
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(item.subtitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.top, 5)
                Text(item.synopsis)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(2)
                    .frame(maxWidth: 430, alignment: .leading)
                    .padding(.top, 14)

                HStack(spacing: 11) {
                    Button { model.selectedItem = item } label: {
                        Label("View Details", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .background(.white, in: Capsule())

                    Button { model.toggleSaved(item) } label: {
                        Label(model.savedIDs.contains(item.id) ? "In My List" : "Add to My List",
                              systemImage: model.savedIDs.contains(item.id) ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .semibold))
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
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text(item.isRemote ? "FROM YOUR CATALOG" : "SAMPLE ARTWORK")
                .font(.system(size: 8, weight: .bold))
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
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        Button { model.selectedItem = item } label: {
                            if landscape { LandscapeCard(item: item) } else { PosterCard(item: item) }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                CardArtwork(item: item)
                    .frame(width: 160, height: 216)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.kind.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.74))
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(13)
                Image(systemName: item.symbol)
                    .font(.system(size: 31, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(item.year.isEmpty ? item.subtitle : "\(item.year) · \(item.subtitle)")
                .font(.system(size: 10))
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
                        .font(.system(size: 22, weight: .light))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                        Text([item.year, item.kind].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 10))
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
                    .font(.system(size: min(size.width, size.height) * 0.29, weight: .ultraLight))
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
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondaryText)
                TextField("Search actors, directors, writers…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Download the IMDb name, cast, and crew datasets from Settings to enable local people search and filmographies.")
                        .font(.system(size: 11))
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .padding(.vertical, 14)
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 26, weight: .ultraLight))
                    Text("No IMDb people matched \(query).")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Text("\(results.count) people · from IMDb's local name index")
                    .font(.system(size: 11))
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
            Image(systemName: "person.crop.square")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.62))
                .frame(width: 48, height: 54)
                .background(LinearGradient(colors: Palette.colors(person.nconst.hashValue), startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(person.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(person.professions.prefix(3).joined(separator: " · ").capitalized)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                Text(person.lifeYears)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondaryText.opacity(0.8))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondaryText)

            HStack(spacing: 14) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 72, height: 78)
                    .background(LinearGradient(colors: Palette.colors(person.nconst.hashValue), startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(person.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(person.professions.prefix(3).joined(separator: " · ").capitalized)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                    Text(person.lifeYears)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if let url = person.imdbURL {
                    Link("IMDb profile", destination: url)
                        .font(.system(size: 11, weight: .medium))
                }
            }

            HStack {
                Text("Filmography")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                Text("IMDb principal cast and crew credits")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText)
            }
            if credits.isEmpty && isLoadingCredits {
                ProgressView("Loading credits…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if credits.isEmpty {
                Text("No movie or TV credits were found for this person in the current IMDb dataset.")
                    .font(.system(size: 11))
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

    private func searchNow() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        Task {
            results = await Task.detached(priority: .userInitiated) {
                IMDbMetadataStore.shared.searchPeople(trimmed)
            }.value
        }
    }

    private func select(_ person: IMDbPersonMetadata) {
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
                        .font(.system(size: 19, weight: .ultraLight))
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
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let rating = credit.title.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.yellow.opacity(0.9))
                        }
                    }
                    Text([credit.title.year.map(String.init), credit.title.kind, credit.category.capitalized]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                    if let characters = credit.characters, !characters.isEmpty {
                        Text(characters)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondaryText.opacity(0.85))
                            .lineLimit(1)
                    } else if let job = credit.job, !job.isEmpty {
                        Text(job)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondaryText.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search this title in the Simba catalog")

            if let url = credit.title.imdbURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                }
                .help("Open IMDb title page")
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
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IMDb Franchise Interests")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Browse franchise pages such as Marvel, Star Wars, Harry Potter, and more.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Link("Open IMDb", destination: IMDbFranchiseBrowser.pageURL)
                    .font(.system(size: 11, weight: .medium))
            }
            Text("IMDb's bulk download does not include franchise membership. This page shows IMDb's live franchise interests; choose a title there to search for it in Simba.")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondaryText.opacity(0.9))
            IMDbFranchiseBrowser()
                .frame(minHeight: 800)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Link("About IMDb franchise interests", destination: URL(string: "https://help.imdb.com/article/contribution/titles/interests/G4Q8HQTQJ6YZ7H7B")!)
                .font(.system(size: 9))
        }
    }
}

private struct IMDbFranchiseBrowser: NSViewRepresentable {
    @EnvironmentObject private var model: LibraryModel
    static let pageURL = URL(string: "https://www.imdb.com/interests/all/")!

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: Self.pageURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var model: LibraryModel?

        init(model: LibraryModel) { self.model = model }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let titleID = Self.titleID(in: url) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            openTitle(titleID)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if let titleID = Self.titleID(in: url) {
                openTitle(titleID)
            } else {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func openTitle(_ titleID: String) {
            Task { [weak self] in
                let metadata = await Task.detached(priority: .userInitiated) {
                    IMDbMetadataStore.shared.title(tconst: titleID)
                }.value
                if let metadata { await self?.model?.openCatalogTitle(matching: metadata) }
            }
        }

        private static func titleID(in url: URL) -> String? {
            guard url.host?.lowercased().hasSuffix("imdb.com") == true else { return nil }
            let components = url.pathComponents
            guard let index = components.firstIndex(of: "title"), components.indices.contains(index + 1) else { return nil }
            let candidate = components[index + 1]
            guard candidate.range(of: #"^tt\d+$"#, options: .regularExpression) != nil else { return nil }
            return candidate
        }
    }
}

private enum IMDbChartTab: String, CaseIterable, Identifiable {
    case topMovies = "Top 250 Movies"
    case topSeries = "Top 250 Series"
    case mostVotedMovies = "Most Voted Movies"
    case mostVotedSeries = "Most Voted Series"
    case trending = "Trending"
    case boxOffice = "Box Office"

    var id: String { rawValue }
}

private enum IMDbTrendingKind: String, CaseIterable, Identifiable {
    case movies = "Movies"
    case series = "TV Shows"

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .movies: URL(string: "https://www.imdb.com/chart/moviemeter/")!
        case .series: URL(string: "https://www.imdb.com/chart/tvmeter/")!
        }
    }
}

private struct IMDbChartsPage: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var selectedTab: IMDbChartTab = .topMovies
    @State private var trendingKind: IMDbTrendingKind = .movies
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedTab.rawValue)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text(selectedTab == .trending
                     ? "Live IMDb popularity charts for movies and TV shows."
                     : "Ranked from the local IMDb ratings and votes dataset. Pick a title to find it in Simba.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }

            Picker("Chart", selection: $selectedTab) {
                ForEach(IMDbChartTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
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
                        .font(.system(size: 12))
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
                    Text("Ranking is calculated from IMDb's public ratings and vote counts; IMDb's exact chart eligibility formula is not included in the downloadable dataset.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondaryText.opacity(0.85))
                    imdbAttribution
                }
            } else {
                emptyDatasetState
            }
        }
        .task { await model.loadIMDbCharts() }
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
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("Refresh IMDb data to build these lists")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("The current local index may only contain TV series. Refresh imports movie ratings too.")
                .font(.system(size: 11))
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
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Live chart from Box Office Mojo by IMDbPro")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Link("Open website", destination: BoxOfficeMojoBrowser.chartURL)
                    .font(.system(size: 11, weight: .medium))
            }
            BoxOfficeMojoBrowser()
                .frame(minHeight: 780)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Box office data is live from Box Office Mojo; it is not included in IMDb's downloadable datasets.")
                .font(.system(size: 9))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
            Link("Information courtesy of Box Office Mojo", destination: URL(string: "https://www.boxofficemojo.com")!)
                .font(.system(size: 9))
        }
    }

    private var trendingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Most Popular · \(trendingKind.rawValue)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Live popularity ranking from IMDb, updated by IMDb's chart.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Link("Open IMDb", destination: trendingKind.url)
                    .font(.system(size: 11, weight: .medium))
            }
            Picker("Trending category", selection: $trendingKind) {
                ForEach(IMDbTrendingKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            IMDbTrendingBrowser(url: trendingKind.url)
                .id(trendingKind.id)
                .frame(minHeight: 780)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("IMDb popularity charts use user interest signals and reflect current trends.")
                .font(.system(size: 9))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
            imdbAttribution
        }
    }

    private var imdbAttribution: some View {
        HStack(spacing: 3) {
            Link("Information courtesy of IMDb", destination: URL(string: "https://www.imdb.com")!)
            Text("(https://www.imdb.com). Used with permission.")
        }
        .font(.system(size: 9))
        .foregroundStyle(Color.secondaryText.opacity(0.85))
    }
}

private struct IMDbTitleCard: View {
    @EnvironmentObject private var model: LibraryModel
    let metadata: IMDbTitleMetadata
    var rank: Int? = nil
    var width: CGFloat = 150
    var artworkHeight: CGFloat = 205
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
                } else {
                    Image(systemName: metadata.kind == "Series" ? "tv" : "film")
                        .font(.system(size: 35, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: width, height: artworkHeight)
                }
                LinearGradient(colors: [.black.opacity(0.22), .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                if let rank {
                    Text("#\(rank)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
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
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .foregroundStyle(.white)
            Text([metadata.year.map(String.init), metadata.rating.map { "★ \(String(format: "%.1f", $0))" }, voteLabel]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 9))
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
        return "\(votes.formatted(.number.notation(.compactName))) votes"
    }
}

private struct BoxOfficeMojoBrowser: NSViewRepresentable {
    static let chartURL = URL(string: "https://www.boxofficemojo.com/chart/ww_top_lifetime_gross/?area=XWW")!

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.load(URLRequest(url: Self.chartURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

private struct IMDbTrendingBrowser: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
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
        Button { model.selectedItem = item } label: { PosterCard(item: item) }
            .buttonStyle(.plain)
    }
}

private struct EmptyLibraryState: View {
    @EnvironmentObject private var model: LibraryModel
    let isWatchlist: Bool
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: isWatchlist ? "bookmark" : (model.searchText.isEmpty ? "film" : "magnifyingglass"))
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(emptyTitle)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(emptyMessage)
                .font(.system(size: 12))
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
        if !model.searchText.isEmpty { return "No matches found" }
        if model.items.isEmpty { return "Your catalog is empty" }
        return "No titles in this section"
    }

    private var emptyMessage: String {
        if isWatchlist { return "Save a movie or show to keep it close." }
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
                    .font(.system(size: 12))
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
                    .font(.system(size: 31, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.48))
                Text("Nothing downloaded yet")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Downloads from movie and episode pages will appear here.")
                    .font(.system(size: 12))
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
                .font(.system(size: 22))
                .foregroundStyle(entry.status == .failed ? Color.orange : Color.white.opacity(0.75))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondaryText)
                    if entry.status == .downloading {
                        if entry.totalBytes == nil {
                            ProgressView().controlSize(.small)
                        } else {
                            ProgressView(value: entry.progress).frame(maxWidth: 170)
                        }
                        Text(byteCount(entry.downloadedBytes, total: entry.totalBytes))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                if let error = entry.errorMessage {
                    Text(error).font(.system(size: 10)).foregroundStyle(Color.orange).lineLimit(2)
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
            Button("Cancel", systemImage: "xmark") { manager.cancel(entry) }
                .labelStyle(.iconOnly)
                .help("Cancel download")
        case .failed, .cancelled:
            Button("Retry", systemImage: "arrow.clockwise") { manager.retry(entry) }
                .labelStyle(.iconOnly)
                .help("Retry download")
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

    private var statusText: String {
        switch entry.status {
        case .completed:
            let partLabel = entry.totalSegments.map { $0 > 1 ? " · \($0) parts" : "" } ?? ""
            return "Downloaded\(partLabel) · \(byteCount(entry.downloadedBytes, total: nil))"
        case .failed: return "Download failed"
        case .cancelled: return "Cancelled"
        case .queued: return "Waiting in queue"
        case .downloading:
            if let totalSegments = entry.totalSegments, totalSegments > 1 {
                return "Downloading · \(entry.completedSegments)/\(totalSegments) parts"
            }
            if entry.totalSegments == 1 { return "Downloading · single part" }
            return "Checking server for range support…"
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
    @State private var selectedSeasonID: String?
    @State private var selectedEpisodeID: String?
    @State private var selectedSourceID: String?
    @State private var isLoadingDetails = false
    @State private var didLoadDetails = false
    @State private var detailsError: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 25) {
                hero

                VStack(alignment: .leading, spacing: 14) {
                    Text([item.kind,
                          details?.year ?? item.year,
                          details?.runtime,
                          displayedRating]
                        .compactMap { $0?.nilIfEmpty }
                        .joined(separator: "  ·  "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondaryText)

                    Text((details?.description ?? item.synopsis).nilIfEmpty ?? "No description is available for this title.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let details, !details.genres.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(details.genres, id: \.self) { genre in
                                Text(genre)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.09), in: Capsule())
                            }
                        }
                    }

                    metadataLine("Director", value: details?.director)
                    metadataLine("Country", value: details?.country)
                    metadataLine("Cast", value: details?.cast.joined(separator: ", "))
                    if details?.imdbID != nil {
                        imdbAttribution
                    }
                }
                .padding(.horizontal, 36)

                if item.kind == "Series" {
                    seriesEpisodes
                    similarSeries
                }

                if isLoadingDetails {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Loading title details from the media API…")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryText)
                    }
                    .padding(.horizontal, 36)
                } else if let detailsError {
                    Text(detailsError)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .padding(.horizontal, 36)
                }
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .onChange(of: selectedSeasonID) { _ in
            selectedEpisodeID = selectedSeason?.episodes.first?.id
            selectedSourceID = nil
        }
        .onChange(of: model.detailsRefreshRevision) { _ in
            guard let refreshed = model.recentlyRefreshedDetails[item.id] else { return }
            details = refreshed
            if selectedSeasonID == nil { selectedSeasonID = refreshed.seasons.first?.id }
            if selectedEpisodeID == nil { selectedEpisodeID = refreshed.seasons.first?.episodes.first?.id }
            if selectedSourceID == nil { selectedSourceID = refreshed.sources.first?.id }
        }
        .task(id: item.id) {
            guard item.isRemote else { return }
            isLoadingDetails = true
            detailsError = nil
            if let loaded = await model.loadDetails(for: item) {
                details = loaded
                selectedSeasonID = loaded.seasons.first?.id
                selectedEpisodeID = loaded.seasons.first?.episodes.first?.id
                selectedSourceID = loaded.sources.first?.id
                didLoadDetails = true
            } else {
                detailsError = "The title details could not be loaded. Check the connection and API settings."
                didLoadDetails = true
            }
            isLoadingDetails = false
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
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
            LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Text(item.kind.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.78))
                Text(item.title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                HStack(spacing: 10) {
                    playButton
                    if let offlineURL = downloadManager.completedDownload(
                        mediaItemID: item.id,
                        episodeID: item.kind == "Series" ? selectedEpisode?.id : nil,
                        title: playbackTitle
                    ) {
                        Label("موجود آفلاین", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.green.opacity(0.9))
                        Button { model.playLocalVideo(offlineURL, title: playbackTitle) } label: {
                            Label("پخش آفلاین", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    downloadControl(
                        sources: activeDownloadSources,
                        title: playbackTitle,
                        label: "Download",
                        episodeID: item.kind == "Series" ? selectedEpisode?.id : nil
                    )
                    if activeSources.count > 1 {
                        Menu {
                            ForEach(activeSources) { source in
                                Button {
                                    selectedSourceID = source.id
                                } label: {
                                    if selectedSourceID == source.id {
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
                    Button { model.toggleSaved(item) } label: {
                        Label(model.savedIDs.contains(item.id) ? "In My List" : "Add to My List",
                              systemImage: model.savedIDs.contains(item.id) ? "checkmark" : "plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .frame(height: 370)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private var displayedRating: String? {
        if let rating = details?.imdbRating { return "IMDb ★ \(rating)" }
        return details?.rating.map { "★ \($0)" }
    }

    private var imdbAttribution: some View {
        HStack(spacing: 3) {
            Link("Information courtesy of IMDb", destination: URL(string: "https://www.imdb.com")!)
            Text("(https://www.imdb.com). Used with permission.")
        }
        .font(.system(size: 9))
        .foregroundStyle(Color.secondaryText.opacity(0.85))
    }

    @ViewBuilder
    private var similarSeries: some View {
        if let details, !details.similarSeries.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Similar by IMDb genres")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("Genre overlap from the IMDb dataset; these are not official IMDb recommendations.")
                        .font(.system(size: 11))
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
                                            .font(.system(size: 17))
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
                    Text(message)
                        .font(.system(size: 11))
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
        if let source = selectedSource {
            Button { beginPlayback(source, title: playbackTitle) } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .help(source.title)
        } else {
            Button {
                dismiss()
                model.openLocalVideo()
            } label: {
                Label(item.isRemote ? (isLoadingDetails ? "Loading…" : "No online source") : "Open a local video",
                      systemImage: item.isRemote ? "exclamationmark.circle" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(item.isRemote || isLoadingDetails)
        }
    }

    @ViewBuilder
    private var seriesEpisodes: some View {
        if let details, !details.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Episodes")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Choose a season and episode to play")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryText)
                    }
                    Spacer()
                    Picker("Season", selection: $selectedSeasonID) {
                        ForEach(details.seasons) { season in
                            Text(season.title).tag(Optional(season.id))
                        }
                    }
                    .frame(width: 180)
                }
                if let season = selectedSeason {
                    VStack(spacing: 9) {
                        ForEach(season.episodes) { episode in
                            episodeRow(episode)
                        }
                    }
                }
            }
            .padding(22)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
            .padding(.horizontal, 36)
        } else if didLoadDetails {
            Text("The API did not return any playable episodes for this series.")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText)
                .padding(.horizontal, 36)
        }
    }

    private func episodeRow(_ episode: MediaEpisode) -> some View {
        let playableSources = uniqueSources(episode.sources + episode.downloadSources)
        let offlineTitle = "\(item.title) · \(episode.title)"
        let offlineURL = downloadManager.completedDownload(
            mediaItemID: item.id,
            episodeID: episode.id,
            title: offlineTitle
        )
        return HStack(spacing: 14) {
            Button { selectedEpisodeID = episode.id; selectedSourceID = nil } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Text(episode.episodeLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.secondaryText)
                        Text(episode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if let duration = episode.duration {
                            Text(duration)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondaryText)
                        }
                        if let rating = episode.imdbRating {
                            Label(rating, systemImage: "star.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.yellow.opacity(0.9))
                                .help("IMDb episode rating")
                        }
                        if let votes = episode.imdbVotes, votes > 0 {
                            Text("\(votes.formatted(.number.notation(.compactName))) votes")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondaryText)
                        }
                        if offlineURL != nil {
                            Label("موجود آفلاین", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.green.opacity(0.9))
                        }
                    }
                    if !episode.synopsis.isEmpty {
                        Text(episode.synopsis)
                            .font(.system(size: 11))
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
                    if let source = playableSources.first {
                        beginPlayback(source, title: offlineTitle, episode: episode)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(playableSources.isEmpty)

                if let offlineURL {
                    Button { model.playLocalVideo(offlineURL, title: offlineTitle) } label: {
                        Label("پخش آفلاین", systemImage: "play.fill")
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
                downloadControl(
                    sources: episode.downloadSources.isEmpty ? episode.sources : episode.downloadSources,
                    title: offlineTitle,
                    label: "Download",
                    episodeID: episode.id
                )
            }
        }
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

    private var activeDownloadSources: [MediaStreamSource] {
        if item.kind == "Series", let episode = selectedEpisode {
            return episode.downloadSources.isEmpty ? episode.sources : episode.downloadSources
        }
        guard let details else { return [] }
        return details.downloadSources.isEmpty ? details.sources : details.downloadSources
    }

    private var selectedSource: MediaStreamSource? {
        if let selectedSourceID, let match = activeSources.first(where: { $0.id == selectedSourceID }) { return match }
        return activeSources.first
    }

    private var playbackTitle: String {
        if item.kind == "Series", let episode = selectedEpisode { return "\(item.title) · \(episode.title)" }
        return item.title
    }

    private func metadataLine(_ label: String, value: String?) -> some View {
        Group {
            if let value = value?.nilIfEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(label).foregroundStyle(Color.secondaryText).frame(width: 66, alignment: .leading)
                    Text(value).foregroundStyle(Color.white.opacity(0.82))
                }
                .font(.system(size: 12))
            }
        }
    }

    private func beginPlayback(_ source: MediaStreamSource, title: String, episode: MediaEpisode? = nil) {
        let playbackEpisode = item.kind == "Series" ? (episode ?? selectedEpisode) : nil
        model.playRemoteSource(source, title: title, item: item, episode: playbackEpisode)
    }

    @ViewBuilder
    private func downloadControl(
        sources: [MediaStreamSource],
        title: String,
        label: String,
        episodeID: String? = nil
    ) -> some View {
        if sources.count == 1, let source = sources.first {
            Button {
                model.downloadManager.enqueue(source: source, title: title, catalogMediaID: item.id, episodeID: episodeID)
            } label: {
                Label(label, systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        } else if !sources.isEmpty {
            Menu {
                ForEach(sources) { source in
                    Button(source.title) {
                        model.downloadManager.enqueue(source: source, title: title, catalogMediaID: item.id, episodeID: episodeID)
                    }
                }
            } label: {
                Label(label, systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        } else {
            Button {} label: {
                Label("No Download Link", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(true)
        }
    }
}

@MainActor
private final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var audioOptions: [AVMediaSelectionOption] = []
    @Published private(set) var subtitleOptions: [AVMediaSelectionOption] = []
    @Published private(set) var subtitlesCanBeDisabled = false

    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var statusObservation: NSKeyValueObservation?
    private var loadedURL: URL?
    private var loadedHeaders: [String: String] = [:]
    private var timeObserver: Any?

    func play(_ url: URL, headers: [String: String]) {
        guard loadedURL != url || loadedHeaders != headers else { player.play(); return }
        loadedURL = url
        loadedHeaders = headers
        audioOptions = []
        subtitleOptions = []
        audioGroup = nil
        subtitleGroup = nil
        errorMessage = nil
        isLoading = true
        currentTimeSeconds = 0

        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                guard time.seconds.isFinite else { return }
                Task { @MainActor [weak self] in
                    self?.currentTimeSeconds = time.seconds
                }
            }
        }

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                case .failed:
                    self.isLoading = false
                    self.errorMessage = Self.playbackDiagnostics(item: item, fallback: message)
                default:
                    break
                }
            }
        }
        Task { await loadTracks(for: item) }
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation = nil
        loadedURL = nil
        loadedHeaders = [:]
    }

    func retry(_ url: URL, headers: [String: String]) {
        loadedURL = nil
        play(url, headers: headers)
    }

    func selectAudio(_ option: AVMediaSelectionOption?) {
        guard let audioGroup else { return }
        player.currentItem?.select(option, in: audioGroup)
    }

    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let subtitleGroup else { return }
        player.currentItem?.select(option, in: subtitleGroup)
    }

    func isAudioSelected(_ option: AVMediaSelectionOption) -> Bool {
        guard let audioGroup else { return false }
        return player.currentItem?.currentMediaSelection.selectedMediaOption(in: audioGroup)?.isEqual(option) == true
    }

    func isSubtitleSelected(_ option: AVMediaSelectionOption) -> Bool {
        guard let subtitleGroup else { return false }
        return player.currentItem?.currentMediaSelection.selectedMediaOption(in: subtitleGroup)?.isEqual(option) == true
    }

    private func loadTracks(for item: AVPlayerItem) async {
        if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
            audioGroup = group
            audioOptions = group.options
        }
        if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            subtitleGroup = group
            subtitleOptions = group.options
            subtitlesCanBeDisabled = group.allowsEmptySelection
        }
    }

    private static func playbackDiagnostics(item: AVPlayerItem, fallback: String?) -> String {
        var lines: [String] = []
        if fallback == "Cannot Open" {
            lines.append("منبع ویدیو باز نشد.")
        } else if let message = fallback, !message.isEmpty {
            lines.append(message)
        } else {
            lines.append("این رسانه باز نشد.")
        }

        if let error = item.error as NSError? {
            lines.append("\(error.domain) (\(error.code))")
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                lines.append("\(underlying.domain) (\(underlying.code))")
            }
        }

        if let event = item.errorLog()?.events.last, event.errorStatusCode != 0 {
            lines.append("HTTP \(event.errorStatusCode)")
        }

        return lines.joined(separator: "\n")
    }
}

private struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFrameSteppingButtons = false
        view.showsSharingServiceButton = false
        view.showsFullScreenToggleButton = true
        view.showsTimecodes = true
        view.allowsPictureInPicturePlayback = true
        view.updatesNowPlayingInfoCenter = true
        view.speeds = [0.5, 0.75, 1, 1.25, 1.5, 2].map {
            AVPlaybackSpeed(rate: Float($0), localizedName: "\($0)×")
        }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

private struct PlayerSubtitleCue: Identifiable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}

enum PlaybackRouting {
    private static let iinaExtensions: Set<String> = ["mkv", "avi", "wmv", "flv", "webm", "mpd"]

    static func usesIINA(for url: URL) -> Bool {
        iinaExtensions.contains(url.pathExtension.lowercased())
    }
}

private struct LocalPlayerSheet: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = PlaybackController()
    let url: URL
    let title: String
    let headers: [String: String]
    @State private var subtitleCues: [PlayerSubtitleCue] = []
    @State private var subtitleDelaySeconds = 0.0
    @State private var subtitleFontSize = 24.0
    @State private var subtitleColor = Color.white
    @State private var subtitleBackgroundOpacity = 0.76
    @State private var didAutoRefreshSource = false
    @State private var didAutoOpenIINA = false
    @State private var isRefreshingSource = false

    private var currentSubtitleCue: PlayerSubtitleCue? {
        subtitleCues.first { cue in
            let subtitleTime = playback.currentTimeSeconds - subtitleDelaySeconds
            return subtitleTime >= cue.start && subtitleTime < cue.end
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            NativePlayerView(player: playback.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let cue = currentSubtitleCue {
                Text(cue.text)
                    .font(.system(size: subtitleFontSize, weight: .semibold))
                    .foregroundStyle(subtitleColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.black.opacity(subtitleBackgroundOpacity), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 66)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }

            LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 138)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.13), in: Circle())
                }
                .buttonStyle(.plain)
                .help("بستن پلیر")

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(url.isFileURL ? "فایل محلی" : (url.host ?? "پخش آنلاین"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()
                ColorPicker("رنگ زیرنویس", selection: $subtitleColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30, height: 28)
                    .help("تغییر رنگ متن زیرنویس")
                subtitleMenu
                trackMenu
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            if playback.isLoading {
                ProgressView("در حال بارگذاری رسانه…")
                    .tint(.white)
                    .padding(16)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let error = playback.errorMessage {
                VStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                    Text("پخش ناموفق").font(.headline)
                    Text(error).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.center)
                    if isRefreshingSource {
                        ProgressView("در حال تازه‌سازی لینک پخش…")
                            .tint(.white)
                    }
                    Button("تازه‌سازی لینک پخش") { refreshPlaybackSource() }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshingSource || !model.hasActiveRemotePlayback)
                    Button("تلاش دوباره") { playback.retry(url, headers: headers) }.buttonStyle(.borderedProminent)
                    Button("باز کردن در IINA") { _ = openInIINA() }.buttonStyle(.bordered)
                }
                .padding(22)
                .frame(maxWidth: 440)
                .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1024, minHeight: 640)
        .background(.black)
        .onAppear {
            if PlaybackRouting.usesIINA(for: url), openInIINA() {
                dismiss()
            } else {
                playback.play(url, headers: headers)
            }
        }
        .onChange(of: playback.errorMessage) { error in
            guard error != nil, !didAutoOpenIINA else { return }
            if url.isFileURL {
                didAutoOpenIINA = true
                if openInIINA() { dismiss() }
                return
            }
            guard model.hasActiveRemotePlayback else { return }
            if didAutoRefreshSource {
                didAutoOpenIINA = true
                if openInIINA() { dismiss() }
                return
            }
            didAutoRefreshSource = true
            refreshPlaybackSource()
        }
        .onDisappear { playback.stop() }
        .onExitCommand { dismiss() }
    }

    private func refreshPlaybackSource() {
        guard !isRefreshingSource, model.hasActiveRemotePlayback else { return }
        isRefreshingSource = true
        Task {
            let source = await model.refreshActivePlaybackSource()
            isRefreshingSource = false
            if let source { playback.retry(source.url, headers: source.headers) }
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button("باز کردن فایل SRT یا VTT…") { chooseSubtitleFile() }
            if !subtitleCues.isEmpty {
                Button("حذف زیرنویس خارجی") { subtitleCues = [] }
                Divider()
                Button("۰٫۵ ثانیه دیرتر") { subtitleDelaySeconds += 0.5 }
                Button("۰٫۵ ثانیه زودتر") { subtitleDelaySeconds -= 0.5 }
                Button("بازنشانی تأخیر") { subtitleDelaySeconds = 0 }
                Divider()
                Button("بزرگ‌تر کردن متن") { subtitleFontSize = min(48, subtitleFontSize + 2) }
                Button("کوچک‌تر کردن متن") { subtitleFontSize = max(14, subtitleFontSize - 2) }
                Button("روشن‌تر کردن پس‌زمینه") { subtitleBackgroundOpacity = min(0.95, subtitleBackgroundOpacity + 0.1) }
                Button("شفاف‌تر کردن پس‌زمینه") { subtitleBackgroundOpacity = max(0.2, subtitleBackgroundOpacity - 0.1) }
            }
        } label: {
            Label("تنظیم زیرنویس", systemImage: "text.bubble")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.13), in: Capsule())
        }
        .menuStyle(.borderlessButton)
    }

    private func chooseSubtitleFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "انتخاب فایل زیرنویس"
        panel.prompt = "باز کردن"
        panel.begin { response in
            guard response == .OK, let fileURL = panel.url else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                guard let contents = Self.decodeSubtitle(data) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                let cues = Self.parseSubtitleCues(contents)
                DispatchQueue.main.async {
                    subtitleCues = cues
                    subtitleDelaySeconds = 0
                }
            } catch {
                DispatchQueue.main.async { subtitleCues = [] }
            }
        }
    }

    private static func decodeSubtitle(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        let encoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringConvertIANACharSetNameToEncoding("windows-1256" as CFString)
        )
        return String(data: data, encoding: String.Encoding(rawValue: encoding))
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func parseSubtitleCues(_ contents: String) -> [PlayerSubtitleCue] {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{feff}", with: "")
        let blocks = normalized.components(separatedBy: "\n\n")
        return blocks.enumerated().compactMap { index, block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = lines[timingIndex].components(separatedBy: "-->")
            guard times.count == 2,
                  let start = Self.subtitleTime(times[0]),
                  let end = Self.subtitleTime(times[1].split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""),
                  end > start else { return nil }
            let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return PlayerSubtitleCue(id: index, start: start, end: end, text: text)
        }
    }

    private static func subtitleTime(_ rawValue: String) -> Double? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let secondsPart = String(parts.last ?? "").replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(secondsPart), let minutes = Double(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? (Double(parts[0]) ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }

    @discardableResult
    private func openInIINA() -> Bool {
        let appURL = URL(fileURLWithPath: "/Applications/IINA.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        return true
    }

    private var trackMenu: some View {
        Menu {
            if !playback.audioOptions.isEmpty {
                Section("صدا") {
                    ForEach(Array(playback.audioOptions.enumerated()), id: \.offset) { entry in
                        let option = entry.element
                        Button {
                            playback.selectAudio(option)
                        } label: {
                            if playback.isAudioSelected(option) {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                }
            }
            if !playback.subtitleOptions.isEmpty || playback.subtitlesCanBeDisabled {
                Section("زیرنویس") {
                    if playback.subtitlesCanBeDisabled {
                        Button("خاموش") { playback.selectSubtitle(nil) }
                    }
                    ForEach(Array(playback.subtitleOptions.enumerated()), id: \.offset) { entry in
                        let option = entry.element
                        Button {
                            playback.selectSubtitle(option)
                        } label: {
                            if playback.isSubtitleSelected(option) {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                }
            }
            if playback.audioOptions.isEmpty && playback.subtitleOptions.isEmpty {
                Text("ترک جایگزینی پیدا نشد")
            }
        } label: {
            Label("صدا و زیرنویس", systemImage: "captions.bubble")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.13), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .help("انتخاب صدا یا زیرنویس")
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var mediaAPIKey = SecretVault.read(account: "media-api-key") ?? ""
    @State private var feedKey = SecretVault.read(account: "catalog-feed-key") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("API connection")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("Direct connection · local SQLite library")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Media API key", systemImage: "key.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                SecureField("API key", text: $mediaAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                SecureField("Catalog feed key", text: $feedKey)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                Text("Values are stored in macOS Keychain. Denbox calls the catalog, search, movie and series APIs directly; the SQLite database stays on this Mac.")
                    .font(.system(size: 10))
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
                    Text(model.connectionStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 9) {
                Label("Local library", systemImage: "square.stack")
                    .font(.system(size: 13, weight: .semibold))
                Text("Catalog: \(model.catalogName)")
                    .font(.system(size: 11))
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
                    .font(.system(size: 13, weight: .semibold))
                Text("Download IMDb's official non-commercial datasets to this Mac. They add local search for actors, directors, and writers, with their movie and TV credits, alongside title and episode ratings, season numbering, and top-rated lists. Episode ratings match by title and then SxxExx numbering. The data is refreshed daily by IMDb but must be downloaded again here to update. IMDb's bulk files do not contain photos, biographies, or franchise membership: title posters are cached from your Simba catalog, and IMDb Franchises browses IMDb's live franchise interests. Trending and box office charts also open live IMDb pages.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text(model.imdbDatasetStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Text("Personal, non-commercial use only. The IMDb files stay local and are not included in app releases.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondaryText.opacity(0.85))
                HStack(spacing: 3) {
                    Link("Information courtesy of IMDb", destination: URL(string: "https://www.imdb.com")!)
                    Text("(https://www.imdb.com). Used with permission.")
                }
                .font(.system(size: 9))
                .foregroundStyle(Color.secondaryText.opacity(0.85))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            Spacer()
            Text("Denbox for Mac · Direct API mode")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondaryText.opacity(0.8))
        }
        .padding(25)
        .frame(width: 620, height: 690)
        .background(Color.canvas)
    }
}

private extension Color {
    static let canvas = Color(red: 0.055, green: 0.061, blue: 0.071)
    static let sidebar = Color(red: 0.085, green: 0.092, blue: 0.102)
    static let secondaryText = Color(red: 0.62, green: 0.65, blue: 0.69)
}
