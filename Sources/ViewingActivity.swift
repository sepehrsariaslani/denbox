import Foundation

struct IMDbGenreFacet: Identifiable, Sendable {
    let name: String
    let titleCount: Int

    var id: String { name }
    var persianName: String { IMDbGenreLocalization.persianName(for: name) }
}

struct WatchProgress: Identifiable, Sendable {
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
    let positionSeconds: Double
    let durationSeconds: Double?
    let watchedSeconds: Double
    let isWatched: Bool
    let updatedAt: Date

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

struct WatchHistoryEntry: Identifiable, Sendable {
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
}

enum PersonalizedRecommendationRanker {
    static func rank(
        _ candidates: [IMDbTitleMetadata],
        history: [WatchHistoryEntry],
        preferredGenres: Set<String>,
        excluding watchedIMDbIDs: Set<String>,
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

        let maximumVotes = max(1, candidates.compactMap(\.votes).max() ?? 1)
        let maximumPopularity = log(Double(maximumVotes) + 1)
        let hasTaste = !weights.isEmpty
        let ranked = candidates.compactMap { title -> (IMDbTitleMetadata, Double)? in
            guard !watchedIMDbIDs.contains(title.tconst),
                  let rating = title.rating, let votes = title.votes, votes >= 50 else { return nil }
            let genreWeight = title.genres.reduce(0.0) { $0 + (weights[$1] ?? 0) }
            let maxWeight = max(1.0, weights.values.max() ?? 1)
            let genreFit = title.genres.isEmpty ? 0 : min(1, genreWeight / (maxWeight * Double(min(title.genres.count, 3))))
            let quality = min(1, max(0, rating / 10))
            let popularity = maximumPopularity > 0 ? log(Double(votes) + 1) / maximumPopularity : 0
            let score = hasTaste
                ? genreFit * 0.68 + quality * 0.22 + popularity * 0.10
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
