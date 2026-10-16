import Foundation

struct PersonalRating: Codable, Sendable {
    let rating: Int
    let item: MediaItem
    let updatedAt: Date
}

struct IMDbGenreFacet: Identifiable, Sendable {
    let name: String
    let titleCount: Int

    var id: String { name }
    var displayName: String { IMDbGenreLocalization.displayName(for: name) }
}

struct WatchProgress: Identifiable, Codable, Sendable {
    let mediaID: String
    let episodeID: String?
    let mediaTitle: String
    let kind: String
    let episodeTitle: String?
    let episodeLabel: String?
    let year: String
    let artworkURL: URL?
    let imdbID: String?
    let genres: [String]
    var positionSeconds: Double
    var durationSeconds: Double?
    var watchedSeconds: Double
    var isWatched: Bool
    var updatedAt: Date

    var id: String { Self.key(mediaID: mediaID, episodeID: episodeID) }
    var displayTitle: String { episodeTitle ?? mediaTitle }
    var progress: Double {
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        return min(1, max(0, positionSeconds / durationSeconds))
    }

    static func key(mediaID: String, episodeID: String?) -> String {
        "\(mediaID)|\(episodeID ?? "")"
    }
}

struct WatchHistoryEntry: Identifiable, Codable, Sendable {
    let id: String
    let mediaID: String
    let episodeID: String?
    let mediaTitle: String
    let kind: String
    let episodeTitle: String?
    let episodeLabel: String?
    let year: String
    let artworkURL: URL?
    let imdbID: String?
    let genres: [String]
    let startedAt: Date
    let positionSeconds: Double
    let durationSeconds: Double?
    let watchedSeconds: Double
    let playerKind: String

    var displayTitle: String { episodeTitle ?? mediaTitle }
}

struct ViewingDataExport: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let progress: [WatchProgress]
    let history: [WatchHistoryEntry]
    let personalRatings: [PersonalRating]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, progress, history, personalRatings
    }

    init(
        schemaVersion: Int,
        exportedAt: Date,
        progress: [WatchProgress],
        history: [WatchHistoryEntry],
        personalRatings: [PersonalRating]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.progress = progress
        self.history = history
        self.personalRatings = personalRatings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        progress = try values.decode([WatchProgress].self, forKey: .progress)
        history = try values.decode([WatchHistoryEntry].self, forKey: .history)
        personalRatings = try values.decodeIfPresent([PersonalRating].self, forKey: .personalRatings) ?? []
    }

    func validated() throws -> ViewingDataExport {
        guard schemaVersion == 1 || schemaVersion == 2 else { throw ViewingDataImportError.unsupportedVersion }
        guard progress.count + history.count + personalRatings.count <= 100_000 else {
            throw ViewingDataImportError.tooManyRecords
        }
        guard exportedAt.timeIntervalSince1970.isFinite else { throw ViewingDataImportError.invalidRecords }

        var progressIDs = Set<String>()
        for entry in progress {
            let key = WatchProgress.key(mediaID: entry.mediaID, episodeID: entry.episodeID)
            guard !entry.mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  progressIDs.insert(key).inserted,
                  entry.positionSeconds.isFinite, entry.positionSeconds >= 0,
                  entry.watchedSeconds.isFinite, entry.watchedSeconds >= 0,
                  entry.durationSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  entry.updatedAt.timeIntervalSince1970.isFinite,
                  ["Movie", "Series"].contains(entry.kind) else {
                throw ViewingDataImportError.invalidRecords
            }
            try Self.validateArtworkURL(entry.artworkURL)
        }

        var historyIDs = Set<String>()
        for entry in history {
            guard !entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  historyIDs.insert(entry.id).inserted,
                  entry.positionSeconds.isFinite, entry.positionSeconds >= 0,
                  entry.watchedSeconds.isFinite, entry.watchedSeconds > 0,
                  entry.durationSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  entry.startedAt.timeIntervalSince1970.isFinite,
                  (entry.startedAt.timeIntervalSince1970 + entry.watchedSeconds).isFinite,
                  ["Movie", "Series"].contains(entry.kind) else {
                throw ViewingDataImportError.invalidRecords
            }
            try Self.validateArtworkURL(entry.artworkURL)
        }

        var ratingIDs = Set<String>()
        for rating in personalRatings {
            guard (1...5).contains(rating.rating),
                  !rating.item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ["Movie", "Series"].contains(rating.item.kind),
                  ratingIDs.insert(rating.item.id).inserted,
                  rating.updatedAt.timeIntervalSince1970.isFinite else {
                throw ViewingDataImportError.invalidRecords
            }
            try Self.validateArtworkURL(rating.item.artworkURL)
        }
        return self
    }

    private static func validateArtworkURL(_ url: URL?) throws {
        guard let url else { return }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw ViewingDataImportError.unsafeArtworkURL
        }
    }
}

enum ViewingDataImportError: LocalizedError {
    case unsupportedVersion
    case tooManyRecords
    case invalidRecords
    case unsafeArtworkURL

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "The selected JSON version is not supported."
        case .tooManyRecords: "The selected JSON contains too many records."
        case .invalidRecords: "The selected JSON contains invalid viewing records."
        case .unsafeArtworkURL: "The selected JSON contains an artwork URL that is not HTTP or HTTPS."
        }
    }
}

struct ViewingDataImportPreview: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let export: ViewingDataExport
}

struct ViewingStats: Sendable {
    var totalWatchedSeconds: Double = 0
    var completedMovies = 0
    var completedEpisodes = 0
    var sessionCount = 0
    var genreSeconds: [String: Double] = [:]

    var watchedHours: Double { totalWatchedSeconds / 3600 }
    var favoriteGenres: [(name: String, seconds: Double)] {
        genreSeconds.map { ($0.key, $0.value) }.sorted { $0.seconds > $1.seconds }
    }
}

enum IMDbGenreLocalization {
    private static let names: [String: String] = [
        "Action": "اکشن",
        "Adventure": "ماجراجویی",
        "Animation": "انیمیشن",
        "Biography": "زندگی‌نامه",
        "Comedy": "کمدی",
        "Crime": "جنایی",
        "Documentary": "مستند",
        "Drama": "درام",
        "Family": "خانوادگی",
        "Fantasy": "فانتزی",
        "Film-Noir": "نوآر",
        "Game-Show": "مسابقه",
        "History": "تاریخی",
        "Horror": "ترسناک",
        "Music": "موسیقی",
        "Musical": "موزیکال",
        "Mystery": "معمایی",
        "News": "خبر",
        "Reality-TV": "واقع‌نما",
        "Romance": "عاشقانه",
        "Sci-Fi": "علمی‌تخیلی",
        "Sport": "ورزشی",
        "Talk-Show": "گفت‌وگو",
        "Thriller": "هیجان‌انگیز",
        "War": "جنگی",
        "Western": "وسترن"
    ]

    static func persianName(for genre: String) -> String {
        names[genre] ?? genre
    }

    static func displayName(for genre: String) -> String {
        guard DenboxLanguage.selectedCode != DenboxLanguage.englishCode else { return genre }
        return persianName(for: genre)
    }
}

enum PersonalizedRecommendationRanker {
    static func rank(
        _ candidates: [IMDbTitleMetadata],
        history: [WatchHistoryEntry],
        preferredGenres: Set<String>,
        excluding watchedIMDbIDs: Set<String>,
        personalRatings: [PersonalRating] = [],
        limit: Int = 60
    ) -> [IMDbTitleMetadata] {
        var weights: [String: Double] = [:]
        for genre in preferredGenres { weights[genre, default: 0] += 3.0 }

        let now = Date()
        for entry in history where entry.watchedSeconds >= 30 {
            let ageDays = max(0, now.timeIntervalSince(entry.startedAt) / 86_400)
            let recency = pow(0.5, ageDays / 45)
            let engagement = min(2.5, max(0.25, entry.watchedSeconds / 1200))
            for genre in entry.genres {
                weights[genre, default: 0] += recency * engagement
            }
        }

        var ratedIMDbIDs = Set<String>()
        var explicitGenreTotals: [String: (weightedScore: Double, weight: Double)] = [:]
        for entry in personalRatings {
            if let imdbID = entry.item.imdbID { ratedIMDbIDs.insert(imdbID) }
            let preference = Double(entry.rating - 3) / 2
            let confidence = abs(preference)
            guard confidence > 0 else { continue }
            for genre in entry.item.genres {
                var total = explicitGenreTotals[genre, default: (0, 0)]
                total.weightedScore += preference * confidence
                total.weight += confidence
                explicitGenreTotals[genre] = total
            }
        }
        let explicitGenrePreferences = explicitGenreTotals.mapValues {
            min(1, max(-1, $0.weightedScore / $0.weight))
        }

        let maximumVotes = max(1, candidates.compactMap(\.votes).max() ?? 1)
        let maximumPopularity = log(Double(maximumVotes) + 1)
        let hasTaste = !weights.isEmpty || !explicitGenrePreferences.isEmpty
        let ranked = candidates.compactMap { title -> (IMDbTitleMetadata, Double)? in
            guard !watchedIMDbIDs.contains(title.tconst), !ratedIMDbIDs.contains(title.tconst),
                  let rating = title.rating, let votes = title.votes, votes >= 50 else { return nil }
            let genreWeight = title.genres.reduce(0.0) { $0 + (weights[$1] ?? 0) }
            let maxWeight = max(1.0, weights.values.max() ?? 1)
            let genreFit = title.genres.isEmpty ? 0 : min(1, genreWeight / (maxWeight * Double(min(title.genres.count, 3))))
            let matchingExplicitPreferences = title.genres.compactMap { explicitGenrePreferences[$0] }
            let explicitGenreFit = explicitGenrePreferences.isEmpty ? nil :
                (matchingExplicitPreferences.isEmpty
                    ? 0.5
                    : matchingExplicitPreferences.map { ($0 + 1) / 2 }.reduce(0, +) / Double(matchingExplicitPreferences.count))
            let tasteFit = explicitGenreFit.map { genreFit * 0.45 + $0 * 0.55 } ?? genreFit
            let quality = min(1, max(0, rating / 10))
            let popularity = maximumPopularity > 0 ? log(Double(votes) + 1) / maximumPopularity : 0
            let score = hasTaste
                ? tasteFit * 0.68 + quality * 0.22 + popularity * 0.10
                : quality * 0.70 + popularity * 0.30
            return (title, score)
        }

        return ranked.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.votes != rhs.0.votes { return (lhs.0.votes ?? 0) > (rhs.0.votes ?? 0) }
            return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }.prefix(max(0, limit)).map(\.0)
    }
}
