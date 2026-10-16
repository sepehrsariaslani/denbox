import Foundation

enum PublicMetadataProvider: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case filimo = "Filimo"
    case hexDL = "HexDL"

    var id: String { rawValue }

    var searchURL: URL? {
        switch self {
        case .filimo: URL(string: "https://www.filimo.com/search")
        case .hexDL: URL(string: "https://hexdl.com/")
        }
    }

    func acceptsSearchPage(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        switch self {
        case .filimo:
            return (host == "filimo.com" || host == "www.filimo.com") && url.path == "/search"
        case .hexDL:
            return (host == "hexdl.com" || host == "www.hexdl.com") && ["/", "/search/"].contains(url.path)
        }
    }

    func accepts(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        switch self {
        case .filimo:
            let parts = url.path.split(separator: "/")
            return (host == "filimo.com" || host == "www.filimo.com")
                && parts.count == 2 && parts[0] == "m"
                && !parts[1].isEmpty && parts[1].allSatisfy { $0.isASCII && $0.isLetterOrNumber }
        case .hexDL:
            let parts = url.path.lowercased().split(separator: "/")
            return (host == "hexdl.com" || host == "www.hexdl.com")
                && url.path != "/"
                && !parts.contains(where: { ["player", "watch", "stream", "download"].contains(String($0)) })
                && !["mp4", "mkv", "webm", "m3u8", "mpd", "srt", "vtt", "torrent"].contains(url.pathExtension.lowercased())
        }
    }
}

private extension Character {
    var isASCII: Bool { unicodeScalars.count == 1 && unicodeScalars.first!.value < 128 }

    var isLetterOrNumber: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }
}

enum PersianMetadataText {
    static func isPersian(_ value: String) -> Bool {
        let letters = value.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar)
                && ((0x0600...0x06FF).contains(scalar.value)
                    || (0xFB50...0xFDFF).contains(scalar.value)
                    || (0xFE70...0xFEFF).contains(scalar.value))
        }
        return letters.count >= 4
    }

    static func preferredSynopsis(from candidates: [String?]) -> String {
        let nonEmpty = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return nonEmpty.first(where: isPersian) ?? nonEmpty.first ?? ""
    }

    static func normalizeTitle(_ value: String) -> String {
        let mapped = String(String.UnicodeScalarView(value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x064A: UnicodeScalar(0x06CC)! // Arabic Yeh -> Persian Yeh
            case 0x0643: UnicodeScalar(0x06A9)! // Arabic Kaf -> Persian Keheh
            case 0x0660...0x0669: UnicodeScalar(0x30 + scalar.value - 0x0660)!
            case 0x06F0...0x06F9: UnicodeScalar(0x30 + scalar.value - 0x06F0)!
            default: scalar
            }
        }))
        let folded = mapped.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }
}

enum PublicMetadataGenreParser {
    private static let canonicalNames: [String: String] = [
        "action": "Action", "اکشن": "Action",
        "adventure": "Adventure", "ماجراجویی": "Adventure",
        "animation": "Animation", "انیمیشن": "Animation",
        "biography": "Biography", "زندگی نامه": "Biography", "زندگی‌نامه": "Biography",
        "comedy": "Comedy", "کمدی": "Comedy",
        "crime": "Crime", "جنایی": "Crime",
        "documentary": "Documentary", "مستند": "Documentary",
        "drama": "Drama", "درام": "Drama",
        "family": "Family", "خانوادگی": "Family",
        "fantasy": "Fantasy", "فانتزی": "Fantasy",
        "film-noir": "Film-Noir", "noir": "Film-Noir", "نوآر": "Film-Noir",
        "game-show": "Game-Show", "مسابقه": "Game-Show",
        "history": "History", "تاریخی": "History",
        "horror": "Horror", "ترسناک": "Horror",
        "music": "Music", "موسیقی": "Music",
        "musical": "Musical", "موزیکال": "Musical",
        "mystery": "Mystery", "معمایی": "Mystery",
        "news": "News", "خبر": "News",
        "reality-tv": "Reality-TV", "واقع نما": "Reality-TV", "واقع‌نما": "Reality-TV",
        "romance": "Romance", "عاشقانه": "Romance",
        "sci-fi": "Sci-Fi", "science fiction": "Sci-Fi", "علمی-تخیلی": "Sci-Fi",
        "علمی تخیلی": "Sci-Fi", "علمی‌تخیلی": "Sci-Fi",
        "short": "Short", "کوتاه": "Short",
        "sport": "Sport", "ورزشی": "Sport",
        "talk-show": "Talk-Show", "گفت و گو": "Talk-Show", "گفت‌وگو": "Talk-Show",
        "thriller": "Thriller", "هیجان انگیز": "Thriller", "هیجان‌انگیز": "Thriller",
        "war": "War", "جنگی": "War",
        "western": "Western", "وسترن": "Western",
        "adult": "Adult", "بزرگسالان": "Adult"
    ]

    static func canonicalName(_ value: String) -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .replacingOccurrences(of: "ـ", with: "")
            .lowercased()
        return canonicalNames[key] ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PublicMetadataCandidate: Sendable {
    let index: Int
    let text: String
    let titleHints: [String]
    let pageURL: URL?
}

enum PublicMetadataTitleMatcher {
    static func bestCandidate(
        in candidates: [PublicMetadataCandidate],
        matching targets: [String],
        kind: String,
        year: String
    ) -> (candidate: PublicMetadataCandidate, score: Double)? {
        let targetNames = targets.map(PersianMetadataText.normalizeTitle).filter { !$0.isEmpty }
        guard !targetNames.isEmpty else { return nil }
        let targetYear = firstYear(in: year).map(gregorianYear)

        let ranked = candidates.compactMap { candidate -> (PublicMetadataCandidate, Double, Int?)? in
            let nameCandidates = (candidate.titleHints + candidate.text
                .split(whereSeparator: \.isNewline).map(String.init))
                .map(PersianMetadataText.normalizeTitle).filter { !$0.isEmpty && $0.count <= 140 }
            let score = nameCandidates.flatMap { name in
                targetNames.map { similarity(name, $0) }
            }.max() ?? 0
            guard score >= 0.93 else { return nil }

            let text = candidate.text.lowercased()
            if kind == "Movie", (text.contains("سریال") || text.contains("series")),
               !text.contains("فیلم") && !text.contains("movie") { return nil }
            if kind == "Series", (text.contains("فیلم") || text.contains("movie")),
               !text.contains("سریال") && !text.contains("series") { return nil }

            let resultYear = firstYear(in: candidate.text).map(gregorianYear)
            let distance = targetYear.flatMap { target in resultYear.map { abs(target - $0) } }
            if let distance, distance > 4 { return nil }
            if targetYear != nil, resultYear == nil, score < 0.99 { return nil }
            if targetNames.contains(where: { $0.count <= 3 && nameCandidates.contains($0) }),
               targetYear == nil || resultYear == nil || (distance ?? Int.max) > 1 { return nil }
            return (candidate, score, distance)
        }

        return ranked.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            return (left.2 ?? Int.max) < (right.2 ?? Int.max)
        }.first.map { ($0.0, $0.1) }
    }

    private static func firstYear(in value: String) -> Int? {
        let digits = value.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 0x0660...0x0669: Character(UnicodeScalar(0x30 + scalar.value - 0x0660)!)
            case 0x06F0...0x06F9: Character(UnicodeScalar(0x30 + scalar.value - 0x06F0)!)
            default: Character(scalar)
            }
        }
        let ascii = String(digits)
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(?:1[234]\d{2}|19\d{2}|20\d{2})(?!\d)"#) else { return nil }
        let range = NSRange(ascii.startIndex..<ascii.endIndex, in: ascii)
        guard let match = regex.firstMatch(in: ascii, range: range),
              let swiftRange = Range(match.range, in: ascii) else { return nil }
        return Int(ascii[swiftRange])
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
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

    private static func gregorianYear(_ year: Int) -> Int {
        guard (1300...1499).contains(year) else { return year }
        var persian = Calendar(identifier: .persian)
        persian.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard let date = persian.date(from: components) else { return year }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = persian.timeZone
        return gregorian.component(.year, from: date)
    }
}

struct PublicTitleMetadata: Codable, Sendable, Identifiable {
    static let currentEnrichmentVersion = 2
    static let currentPageDetailsVersion = 2

    let provider: PublicMetadataProvider
    let pageURL: URL
    var title: String
    var synopsis: String
    var posterURL: URL?
    let visiblePageText: String
    let visibleHeadings: [String]
    let episodeSnippets: [String]
    let imageURLs: [URL]
    let importedAt: Date
    var originalTitle: String? = nil
    var year: String? = nil
    var country: String? = nil
    var contentRating: String? = nil
    var publicRating: String? = nil
    var ratingSource: String? = nil
    var communityRating: String? = nil
    var communityVotes: String? = nil
    var runtime: String? = nil
    var director: String? = nil
    var genres: [String]? = nil
    var seasonCount: Int? = nil
    var episodeCount: Int? = nil
    var castNames: [String]? = nil
    var crewNames: [String]? = nil
    var publicBadges: [String]? = nil
    var enrichmentVersion: Int? = currentEnrichmentVersion
    var pageDetailsVersion: Int? = nil
    var pageDetailsAttemptedAt: Date? = nil

    var id: String { "\(provider.rawValue):\(pageURL.absoluteString)" }

    var hasPersianSynopsis: Bool { PersianMetadataText.isPersian(synopsis) }

    func needsAutomaticRefresh(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(importedAt)
        return age > 30 * 24 * 60 * 60 || !hasPersianSynopsis || posterURL == nil
            || enrichmentVersion != Self.currentEnrichmentVersion
    }

    func needsPageDetailsRefresh(now: Date = Date()) -> Bool {
        guard pageDetailsVersion != Self.currentPageDetailsVersion else { return false }
        guard let pageDetailsAttemptedAt else { return true }
        return now.timeIntervalSince(pageDetailsAttemptedAt) >= PublicTitleMetadataRefreshPolicy.retryInterval
    }

    func merging(_ fallback: PublicTitleMetadata) -> PublicTitleMetadata {
        let preferredSynopsis: String
        if PersianMetadataText.isPersian(synopsis) {
            preferredSynopsis = synopsis
        } else if PersianMetadataText.isPersian(fallback.synopsis) {
            preferredSynopsis = fallback.synopsis
        } else if !synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferredSynopsis = synopsis
        } else {
            preferredSynopsis = fallback.synopsis
        }
        return PublicTitleMetadata(
            provider: provider,
            pageURL: pageURL,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback.title : title,
            synopsis: preferredSynopsis,
            posterURL: posterURL ?? fallback.posterURL,
            visiblePageText: visiblePageText.isEmpty ? fallback.visiblePageText : visiblePageText,
            visibleHeadings: Self.mergeStrings(visibleHeadings + fallback.visibleHeadings, limit: 100),
            episodeSnippets: Self.mergeStrings(episodeSnippets + fallback.episodeSnippets, limit: 150),
            imageURLs: Self.mergeURLs(imageURLs + fallback.imageURLs, limit: 40),
            importedAt: max(importedAt, fallback.importedAt),
            originalTitle: Self.nonEmpty(originalTitle) ?? fallback.originalTitle,
            year: Self.nonEmpty(year) ?? fallback.year,
            country: Self.nonEmpty(country) ?? fallback.country,
            contentRating: Self.nonEmpty(contentRating) ?? fallback.contentRating,
            publicRating: Self.nonEmpty(publicRating) ?? fallback.publicRating,
            ratingSource: Self.nonEmpty(ratingSource) ?? fallback.ratingSource,
            communityRating: Self.nonEmpty(communityRating) ?? fallback.communityRating,
            communityVotes: Self.nonEmpty(communityVotes) ?? fallback.communityVotes,
            runtime: Self.nonEmpty(runtime) ?? fallback.runtime,
            director: Self.nonEmpty(director) ?? fallback.director,
            genres: Self.mergeOptionalStrings(genres, fallback.genres, limit: 12),
            seasonCount: seasonCount ?? fallback.seasonCount,
            episodeCount: episodeCount ?? fallback.episodeCount,
            castNames: Self.mergeOptionalStrings(castNames, fallback.castNames, limit: 40),
            crewNames: Self.mergeOptionalStrings(crewNames, fallback.crewNames, limit: 30),
            publicBadges: Self.mergeOptionalStrings(publicBadges, fallback.publicBadges, limit: 20),
            enrichmentVersion: max(enrichmentVersion ?? 0, fallback.enrichmentVersion ?? 0) == 0
                ? nil : max(enrichmentVersion ?? 0, fallback.enrichmentVersion ?? 0),
            pageDetailsVersion: pageDetailsVersion ?? fallback.pageDetailsVersion,
            pageDetailsAttemptedAt: [pageDetailsAttemptedAt, fallback.pageDetailsAttemptedAt]
                .compactMap { $0 }.max()
        )
    }

    private static func mergeOptionalStrings(_ first: [String]?, _ second: [String]?, limit: Int) -> [String]? {
        var seen = Set<String>()
        let values = Array(((first ?? []) + (second ?? [])).filter { seen.insert($0).inserted }.prefix(limit))
        return values.isEmpty ? nil : values
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mergeStrings(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(values.filter { seen.insert($0).inserted }.prefix(limit))
    }

    private static func mergeURLs(_ values: [URL], limit: Int) -> [URL] {
        var seen = Set<URL>()
        return Array(values.filter { seen.insert($0).inserted }.prefix(limit))
    }

    func editing(title: String, synopsis: String) -> PublicTitleMetadata {
        PublicTitleMetadata(
            provider: provider,
            pageURL: pageURL,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            synopsis: synopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            posterURL: posterURL,
            visiblePageText: visiblePageText,
            visibleHeadings: visibleHeadings,
            episodeSnippets: episodeSnippets,
            imageURLs: imageURLs,
            importedAt: importedAt,
            originalTitle: originalTitle,
            year: year,
            country: country,
            contentRating: contentRating,
            publicRating: publicRating,
            ratingSource: ratingSource,
            communityRating: communityRating,
            communityVotes: communityVotes,
            runtime: runtime,
            director: director,
            genres: genres,
            seasonCount: seasonCount,
            episodeCount: episodeCount,
            castNames: castNames,
            crewNames: crewNames,
            publicBadges: publicBadges,
            enrichmentVersion: enrichmentVersion,
            pageDetailsVersion: pageDetailsVersion,
            pageDetailsAttemptedAt: pageDetailsAttemptedAt
        )
    }
}

enum PublicTitleMetadataRefreshPolicy {
    // Version the provider search strategy so attempts made by an older, failing
    // WebKit-only lookup do not suppress the first run of the direct public APIs.
    static let lookupVersion = 3
    static let retryInterval: TimeInterval = 24 * 60 * 60

    static func shouldRefresh(
        cached: PublicTitleMetadata?,
        lastAttempt: Date?,
        now: Date = Date(),
        force: Bool = false
    ) -> Bool {
        guard force || (cached?.needsAutomaticRefresh(now: now) ?? true) else { return false }
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < retryInterval { return false }
        return true
    }
}
