import Foundation

struct MetadataCitation: Codable, Equatable, Identifiable, Sendable {
    let provider: String
    let url: URL

    var id: String { provider }
}

struct TVmazeCastMemberMetadata: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let character: String?
    let imageURL: URL?
    let imdbID: String?
    let tvmazeID: Int?
    let tvmazeURL: URL?

    var id: String {
        if let imdbID { return "imdb:\(imdbID.lowercased())" }
        if let tvmazeID { return "tvmaze:\(tvmazeID)" }
        return "name:\(MediaTitleMatching.normalize(name))"
    }
}

struct ReferenceTitleMetadata: Codable, Sendable {
    var synopsis: String?
    var posterURL: URL?
    var year: String?
    var rating: String?
    var runtime: String?
    var genres: [String]
    var country: String?
    var director: String?
    var cast: [String]
    var citations: [MetadataCitation]
    var attemptedProviders: [String]
    var fetchedAt: Date
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
    var castProfiles: [TVmazeCastMemberMetadata]? = nil
    var tvmazeCastProfilesVersion: Int? = nil
    var wikidataLookupIMDbID: String? = nil

    static func empty(fetchedAt: Date = Date()) -> Self {
        Self(synopsis: nil, posterURL: nil, year: nil, rating: nil, runtime: nil,
             genres: [], country: nil, director: nil, cast: [], citations: [], attemptedProviders: [], fetchedAt: fetchedAt)
    }

    var isEmpty: Bool {
        synopsis == nil && posterURL == nil && year == nil && rating == nil && runtime == nil
            && genres.isEmpty && country == nil && director == nil && cast.isEmpty && citations.isEmpty
            && tagline == nil && originalTitle == nil && status == nil && contentRating == nil
            && originalLanguage == nil && seasonCount == nil && episodeCount == nil
            && networks == nil && productionCompanies == nil && writers == nil && keywords == nil
            && trailerURL == nil && homepageURL == nil && backdropURL == nil
            && castProfiles?.isEmpty != false
    }

    func merging(_ fallback: Self) -> Self {
        let citationMap = Dictionary((citations + fallback.citations).map { ($0.provider, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let castProfilesVersion = max(tvmazeCastProfilesVersion ?? 0, fallback.tvmazeCastProfilesVersion ?? 0)
        return Self(
            synopsis: Self.preferredSynopsis(synopsis, fallback.synopsis),
            posterURL: posterURL ?? fallback.posterURL,
            year: year ?? fallback.year,
            rating: rating ?? fallback.rating,
            runtime: runtime ?? fallback.runtime,
            genres: Array((genres + fallback.genres).referenceUniqued().prefix(12)),
            country: country ?? fallback.country,
            director: director ?? fallback.director,
            cast: Array((cast + fallback.cast).referenceUniqued().prefix(20)),
            citations: citationMap.values.sorted { $0.provider < $1.provider },
            attemptedProviders: Array(Set(attemptedProviders + fallback.attemptedProviders)).sorted(),
            fetchedAt: max(fetchedAt, fallback.fetchedAt),
            ratingSource: ratingSource ?? fallback.ratingSource,
            tagline: tagline ?? fallback.tagline,
            originalTitle: originalTitle ?? fallback.originalTitle,
            status: status ?? fallback.status,
            contentRating: contentRating ?? fallback.contentRating,
            originalLanguage: originalLanguage ?? fallback.originalLanguage,
            seasonCount: seasonCount ?? fallback.seasonCount,
            episodeCount: episodeCount ?? fallback.episodeCount,
            networks: Self.mergeLists(networks, fallback.networks, limit: 12),
            productionCompanies: Self.mergeLists(productionCompanies, fallback.productionCompanies, limit: 12),
            writers: Self.mergeLists(writers, fallback.writers, limit: 20),
            keywords: Self.mergeLists(keywords, fallback.keywords, limit: 30),
            trailerURL: trailerURL ?? fallback.trailerURL,
            homepageURL: homepageURL ?? fallback.homepageURL,
            backdropURL: backdropURL ?? fallback.backdropURL,
            castProfiles: Self.mergeCastProfiles(castProfiles, fallback.castProfiles),
            tvmazeCastProfilesVersion: castProfilesVersion == 0 ? nil : castProfilesVersion,
            wikidataLookupIMDbID: wikidataLookupIMDbID ?? fallback.wikidataLookupIMDbID
        )
    }

    private static func mergeLists(_ first: [String]?, _ second: [String]?, limit: Int) -> [String]? {
        let values = ((first ?? []) + (second ?? [])).referenceUniqued().prefix(limit)
        return values.isEmpty ? nil : Array(values)
    }

    private static func preferredSynopsis(_ first: String?, _ second: String?) -> String? {
        let primary = first?.trimmingCharacters(in: .whitespacesAndNewlines).referenceNonEmpty
        let fallback = second?.trimmingCharacters(in: .whitespacesAndNewlines).referenceNonEmpty
        if let primary, PersianMetadataText.isPersian(primary) { return primary }
        if let fallback, PersianMetadataText.isPersian(fallback) { return fallback }
        return primary ?? fallback
    }

    private static func mergeCastProfiles(
        _ first: [TVmazeCastMemberMetadata]?,
        _ second: [TVmazeCastMemberMetadata]?
    ) -> [TVmazeCastMemberMetadata]? {
        var order: [String] = []
        var profiles: [String: TVmazeCastMemberMetadata] = [:]
        for member in (first ?? []) + (second ?? []) {
            guard !member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let existing = profiles[member.id] {
                profiles[member.id] = TVmazeCastMemberMetadata(
                    name: existing.name,
                    character: existing.character ?? member.character,
                    imageURL: existing.imageURL ?? member.imageURL,
                    imdbID: existing.imdbID ?? member.imdbID,
                    tvmazeID: existing.tvmazeID ?? member.tvmazeID,
                    tvmazeURL: existing.tvmazeURL ?? member.tvmazeURL
                )
            } else {
                order.append(member.id)
                profiles[member.id] = member
            }
        }
        let result = order.prefix(20).compactMap { profiles[$0] }
        return result.isEmpty ? nil : result
    }
}

enum ReferenceMetadataService {
    private static let cacheLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let emptyCacheLifetime: TimeInterval = 24 * 60 * 60
    private static let tvmazeCastProfilesVersion = 1

    static func shouldRefresh(
        _ cached: ReferenceTitleMetadata?,
        for item: MediaItem,
        imdbID: String?,
        hasTMDBToken: Bool = false,
        forceTMDB: Bool = false
    ) -> Bool {
        guard let cached else { return true }
        let age = Date().timeIntervalSince(cached.fetchedAt)
        let stale = age > (cached.isEmpty ? emptyCacheLifetime : cacheLifetime)
        if stale { return true }
        if needsTVmazeRefresh(for: item, cached: cached, stale: false) { return true }
        if needsWikidataRefresh(for: item, cached: cached, imdbID: imdbID, stale: false) { return true }
        let attempted = Set(cached.attemptedProviders)
        if hasTMDBToken, forceTMDB || !attempted.contains("TMDB") { return true }
        return false
    }

    private static func needsWikidataRefresh(
        for item: MediaItem,
        cached: ReferenceTitleMetadata?,
        imdbID: String?,
        stale: Bool
    ) -> Bool {
        guard item.kind == "Movie" || item.kind == "Series" else { return false }
        guard let cached else { return true }
        if stale || !cached.attemptedProviders.contains("Wikidata") { return true }
        guard validIMDbID(imdbID) else { return false }
        return cached.wikidataLookupIMDbID != imdbID
    }

    static func needsTVmazeRefresh(for item: MediaItem, cached: ReferenceTitleMetadata?, stale: Bool) -> Bool {
        guard item.kind == "Series" else { return false }
        guard let cached else { return true }
        let attempted = Set(cached.attemptedProviders)
        let hasTVmazeMetadata = cached.citations.contains { $0.provider == "TVmaze" }
            || cached.castProfiles?.isEmpty == false
        return stale || !attempted.contains("TVmaze")
            || (hasTVmazeMetadata && cached.tvmazeCastProfilesVersion != tvmazeCastProfilesVersion)
    }

    static func enrich(_ details: MediaDetails, with metadata: ReferenceTitleMetadata) -> MediaDetails {
        MediaDetails(
            description: details.description?.referenceNonEmpty ?? metadata.synopsis,
            year: details.year?.referenceNonEmpty ?? metadata.year,
            rating: details.rating?.referenceNonEmpty ?? metadata.rating,
            runtime: details.runtime?.referenceNonEmpty ?? metadata.runtime,
            genres: details.genres.isEmpty ? metadata.genres : details.genres,
            country: details.country?.referenceNonEmpty ?? metadata.country,
            director: details.director?.referenceNonEmpty ?? metadata.director,
            cast: Array((details.cast + metadata.cast).referenceUniqued().prefix(20)),
            sources: details.sources,
            downloadSources: details.downloadSources,
            seasons: details.seasons,
            imdbID: details.imdbID,
            imdbRating: details.imdbRating,
            imdbVotes: details.imdbVotes,
            similarSeries: details.similarSeries,
            castPeople: details.castPeople,
            ratingSource: details.rating?.referenceNonEmpty == nil ? metadata.ratingSource : details.ratingSource,
            tagline: details.tagline ?? metadata.tagline,
            originalTitle: details.originalTitle ?? metadata.originalTitle,
            status: details.status ?? metadata.status,
            contentRating: details.contentRating ?? metadata.contentRating,
            originalLanguage: details.originalLanguage ?? metadata.originalLanguage,
            seasonCount: details.seasonCount ?? metadata.seasonCount,
            episodeCount: details.episodeCount ?? metadata.episodeCount,
            networks: Self.mergeLists(details.networks, metadata.networks, limit: 12),
            productionCompanies: Self.mergeLists(details.productionCompanies, metadata.productionCompanies, limit: 12),
            writers: Self.mergeLists(details.writers, metadata.writers, limit: 20),
            keywords: Self.mergeLists(details.keywords, metadata.keywords, limit: 30),
            trailerURL: details.trailerURL ?? metadata.trailerURL,
            homepageURL: details.homepageURL ?? metadata.homepageURL,
            backdropURL: details.backdropURL ?? metadata.backdropURL
        )
    }

    private static func mergeLists(_ first: [String]?, _ second: [String]?, limit: Int) -> [String]? {
        let values = ((first ?? []) + (second ?? [])).referenceUniqued().prefix(limit)
        return values.isEmpty ? nil : Array(values)
    }

    static func fetch(
        for item: MediaItem,
        imdbID: String?,
        existing: ReferenceTitleMetadata?,
        tmdbToken: String? = nil,
        forceTMDB: Bool = false
    ) async -> ReferenceTitleMetadata {
        let existingAge = existing.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity
        let stale = existingAge > ((existing?.isEmpty ?? true) ? emptyCacheLifetime : cacheLifetime)
        let wantsTVmaze = needsTVmazeRefresh(for: item, cached: existing, stale: stale)
        let wantsWikidata = needsWikidataRefresh(for: item, cached: existing, imdbID: imdbID, stale: stale)
        let attempted = Set(existing?.attemptedProviders ?? [])
        let hasTMDBToken = !(tmdbToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let wantsTMDB = hasTMDBToken && (stale || forceTMDB || !attempted.contains("TMDB"))
        guard wantsTVmaze || wantsWikidata || wantsTMDB else {
            var unchanged = existing ?? .empty()
            unchanged.fetchedAt = Date()
            return unchanged
        }

        let fetched: [ReferenceTitleMetadata?] = await withTaskGroup(of: ReferenceTitleMetadata?.self) { group in
            if wantsTVmaze { group.addTask { await fetchTVmaze(item: item, imdbID: imdbID) } }
            if wantsWikidata { group.addTask { await fetchWikidata(item: item, imdbID: imdbID) } }
            if wantsTMDB, let tmdbToken {
                group.addTask { await fetchTMDB(item: item, imdbID: imdbID, accessToken: tmdbToken) }
            }
            var values: [ReferenceTitleMetadata?] = []
            for await value in group { values.append(value) }
            return values
        }

        var result = ReferenceTitleMetadata.empty()
        let orderedParts = fetched.compactMap({ $0 }).sorted { left, right in
            sourcePriority(left) < sourcePriority(right)
        }
        for part in orderedParts {
            result = result.merging(part)
        }
        if let existing { result = result.merging(existing) }
        if wantsTVmaze { result.attemptedProviders.appendIfUnique("TVmaze") }
        if wantsTVmaze { result.tvmazeCastProfilesVersion = Self.tvmazeCastProfilesVersion }
        if wantsWikidata {
            result.attemptedProviders.appendIfUnique("Wikidata")
            if validIMDbID(imdbID) { result.wikidataLookupIMDbID = imdbID }
        }
        if wantsTMDB { result.attemptedProviders.appendIfUnique("TMDB") }
        result.fetchedAt = Date()
        return result
    }

    private static func fetchTMDB(item: MediaItem, imdbID: String?, accessToken: String) async -> ReferenceTitleMetadata? {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, item.kind == "Movie" || item.kind == "Series" else { return nil }
        let mediaType = item.kind == "Movie" ? "movie" : "tv"
        guard let candidate = await findTMDBCandidate(item: item, imdbID: imdbID, mediaType: mediaType, accessToken: token),
              let identifier = number(candidate, key: "id"), identifier > 0 else { return nil }
        let detailPath = "https://api.themoviedb.org/3/\(mediaType)/\(Int(identifier))"
        let appended = mediaType == "movie"
            ? "credits,videos,keywords,release_dates"
            : "credits,videos,keywords,content_ratings"
        guard let url = makeURL(detailPath, query: [
            URLQueryItem(name: "append_to_response", value: appended),
            URLQueryItem(name: "language", value: "en-US")
        ]), let payload = await getTMDBJSON(url, accessToken: token),
           let details = payload as? [String: Any] else { return nil }
        return parseTMDB(details, mediaType: mediaType)
    }

    private static func findTMDBCandidate(item: MediaItem, imdbID: String?, mediaType: String, accessToken: String) async -> [String: Any]? {
        if let imdbID, validIMDbID(imdbID),
           let url = makeURL("https://api.themoviedb.org/3/find/\(imdbID)", query: [
            URLQueryItem(name: "external_source", value: "imdb_id")
           ]),
           let payload = await getTMDBJSON(url, accessToken: accessToken),
           let root = payload as? [String: Any],
           let results = root[mediaType == "movie" ? "movie_results" : "tv_results"] as? [[String: Any]],
           let match = results.first {
            return match
        }

        let targetYear = item.year.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression)
            .flatMap { Int(item.year[$0]) }
        for title in ([item.title] + item.matchingTitles).referenceUniqued().prefix(2) {
            var query = [URLQueryItem(name: "query", value: title), URLQueryItem(name: "include_adult", value: "false")]
            if let targetYear {
                query.append(URLQueryItem(name: mediaType == "movie" ? "primary_release_year" : "first_air_date_year", value: String(targetYear)))
            }
            guard let url = makeURL("https://api.themoviedb.org/3/search/\(mediaType)", query: query),
                  let payload = await getTMDBJSON(url, accessToken: accessToken),
                  let results = (payload as? [String: Any])?["results"] as? [[String: Any]],
                  let match = bestTMDBCandidate(in: results, item: item, mediaType: mediaType) else { continue }
            return match
        }
        return nil
    }

    static func bestTMDBCandidate(in candidates: [[String: Any]], item: MediaItem, mediaType: String) -> [String: Any]? {
        let titleKeys = mediaType == "movie" ? ["title", "original_title"] : ["name", "original_name"]
        let targetNames = ([item.title] + item.matchingTitles).map(MediaTitleMatching.normalize)
        let targetYear = item.year.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression)
            .flatMap { Int(item.year[$0]) }
        let ranked = candidates.compactMap { candidate -> (row: [String: Any], score: Double, yearDistance: Int?, popularity: Double)? in
            let names = titleKeys.compactMap { string(candidate[$0]) }.map(MediaTitleMatching.normalize)
            let score = names.flatMap { name in targetNames.map { MediaTitleMatching.similarity(name, $0) } }.max() ?? 0
            guard score >= 0.88 else { return nil }
            let dateField = mediaType == "movie" ? "release_date" : "first_air_date"
            let resultYear = string(candidate[dateField]).flatMap { Int($0.prefix(4)) }
            let yearDistance = targetYear.flatMap { target in resultYear.map { abs(target - $0) } }
            if let yearDistance, yearDistance > 3, score < 0.98 { return nil }
            if targetYear != nil, resultYear == nil, score < 0.98 { return nil }
            return (candidate, score, yearDistance, number(candidate, key: "popularity") ?? 0)
        }
        return ranked.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            if left.yearDistance != right.yearDistance { return (left.yearDistance ?? Int.max) < (right.yearDistance ?? Int.max) }
            return left.popularity > right.popularity
        }.first?.row
    }

    static func parseTMDB(_ payload: [String: Any], mediaType: String) -> ReferenceTitleMetadata? {
        guard let identifier = number(payload, key: "id"), identifier > 0 else { return nil }
        let id = Int(identifier)
        let originalTitleField = mediaType == "movie" ? "original_title" : "original_name"
        let dateField = mediaType == "movie" ? "release_date" : "first_air_date"
        let year = string(payload[dateField]).flatMap { date -> String? in
            let value = String(date.prefix(4))
            return value.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) == nil ? nil : value
        }
        let credits = payload["credits"] as? [String: Any] ?? [:]
        let cast = Array((credits["cast"] as? [[String: Any]] ?? []).compactMap { string($0["name"]) }.referenceUniqued().prefix(20))
        let crew = credits["crew"] as? [[String: Any]] ?? []
        let directors = crew.filter { string($0["job"])?.localizedCaseInsensitiveCompare("Director") == .orderedSame }
            .compactMap { string($0["name"]) }.referenceUniqued()
        let creators = (payload["created_by"] as? [[String: Any]] ?? []).compactMap { string($0["name"]) }.referenceUniqued()
        let writers = crew.filter {
            guard let job = string($0["job"])?.lowercased() else { return false }
            return ["writer", "screenplay", "story", "teleplay", "creator"].contains(job)
        }.compactMap { string($0["name"]) }.referenceUniqued()
        let genres = Array((payload["genres"] as? [[String: Any]] ?? []).compactMap { string($0["name"]) }.referenceUniqued().prefix(12))
        let productionCompanies = Array((payload["production_companies"] as? [[String: Any]] ?? []).compactMap { string($0["name"]) }.referenceUniqued().prefix(12))
        let networks = Array((payload["networks"] as? [[String: Any]] ?? []).compactMap { string($0["name"]) }.referenceUniqued().prefix(12))
        let productionCountries = (payload["production_countries"] as? [[String: Any]] ?? []).compactMap { string($0["name"]) }
        let originCountries = (payload["origin_country"] as? [String] ?? [])
        let country = (productionCountries.isEmpty ? originCountries : productionCountries).prefix(5).joined(separator: ", ").referenceNonEmpty
        let rating = number(payload, key: "vote_average").flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
        let runtimeValue = number(payload, key: "runtime") ?? (payload["episode_run_time"] as? [NSNumber])?.first?.doubleValue
        let runtime = runtimeValue.flatMap { $0 > 0 && $0 < 1000 ? "\(Int($0.rounded())) min" : nil }
        let videos = (payload["videos"] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        let trailer = videos.filter {
            string($0["site"])?.localizedCaseInsensitiveCompare("YouTube") == .orderedSame
                && string($0["type"])?.localizedCaseInsensitiveCompare("Trailer") == .orderedSame
        }.sorted { (number($0, key: "official") ?? 0) > (number($1, key: "official") ?? 0) }
            .compactMap { string($0["key"]) }
            .first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }
        let keywordObject = payload["keywords"] as? [String: Any] ?? [:]
        let keywordRows = (keywordObject["keywords"] as? [[String: Any]]) ?? (keywordObject["results"] as? [[String: Any]]) ?? []
        let keywords = Array(keywordRows.compactMap { string($0["name"]) }.referenceUniqued().prefix(30))
        let contentRating = tmdbContentRating(payload, mediaType: mediaType)
        let homepageURL = string(payload["homepage"]).flatMap(httpsURL)
        let citationURL = URL(string: "https://www.themoviedb.org/\(mediaType == "movie" ? "movie" : "tv")/\(id)")!

        return ReferenceTitleMetadata(
            synopsis: string(payload["overview"]),
            posterURL: tmdbImageURL(payload["poster_path"], size: "w500"),
            year: year,
            rating: rating,
            runtime: runtime,
            genres: genres,
            country: country,
            director: (mediaType == "tv" ? creators : []).first ?? directors.first,
            cast: cast,
            citations: [MetadataCitation(provider: "TMDB", url: citationURL)],
            attemptedProviders: ["TMDB"],
            fetchedAt: Date(),
            ratingSource: rating == nil ? nil : "TMDB",
            tagline: string(payload["tagline"]),
            originalTitle: string(payload[originalTitleField]),
            status: string(payload["status"]),
            contentRating: contentRating,
            originalLanguage: string(payload["original_language"]),
            seasonCount: integer(payload, key: "number_of_seasons"),
            episodeCount: integer(payload, key: "number_of_episodes"),
            networks: networks.isEmpty ? nil : networks,
            productionCompanies: productionCompanies.isEmpty ? nil : productionCompanies,
            writers: writers.isEmpty ? nil : Array(writers.prefix(20)),
            keywords: keywords.isEmpty ? nil : keywords,
            trailerURL: trailer,
            homepageURL: homepageURL,
            backdropURL: tmdbImageURL(payload["backdrop_path"], size: "w1280")
        )
    }

    private static func tmdbContentRating(_ payload: [String: Any], mediaType: String) -> String? {
        let rootKey = mediaType == "movie" ? "release_dates" : "content_ratings"
        let rows = (payload[rootKey] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        let usRow = rows.first { string($0["iso_3166_1"]) == "US" }
        if mediaType == "movie" {
            let releases = usRow?["release_dates"] as? [[String: Any]] ?? []
            return releases.compactMap { string($0["certification"]) }
                .first(where: { !$0.isEmpty }).map { "US · \($0)" }
        }
        return usRow.flatMap { string($0["rating"]) }.map { "US · \($0)" }
    }

    private static func getTMDBJSON(_ url: URL, accessToken: String) async -> Any? {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Denbox/1.0 (macOS media library; metadata lookup)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func tmdbImageURL(_ raw: Any?, size: String) -> URL? {
        guard let path = string(raw), path.hasPrefix("/"), !path.contains("..") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    private static func httpsURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func integer(_ object: [String: Any]?, key: String) -> Int? {
        guard let value = number(object, key: key), value.isFinite, value >= 0, value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    static func parseTVmaze(_ payload: Any, item: MediaItem, imdbID: String?) -> ReferenceTitleMetadata? {
        guard item.kind == "Series", let show = bestTVmazeShow(in: payload, item: item, imdbID: imdbID) else { return nil }
        let embedded = show["_embedded"] as? [String: Any] ?? [:]
        let castRows = embedded["cast"] as? [[String: Any]] ?? []
        var castProfiles: [TVmazeCastMemberMetadata] = []
        var seenCast = Set<String>()
        for row in castRows {
            guard let person = row["person"] as? [String: Any],
                  let name = string(person["name"]) else { continue }
            let image = person["image"] as? [String: Any]
            let externals = person["externals"] as? [String: Any]
            let member = TVmazeCastMemberMetadata(
                name: name,
                character: (row["character"] as? [String: Any]).flatMap { string($0["name"]) },
                imageURL: (string(image?["original"]) ?? string(image?["medium"])).flatMap(httpsURL),
                imdbID: string(externals?["imdb"]),
                tvmazeID: integer(person, key: "id"),
                tvmazeURL: string(person["url"]).flatMap(httpsURL)
            )
            guard seenCast.insert(member.id).inserted else { continue }
            castProfiles.append(member)
            if castProfiles.count == 20 { break }
        }
        let cast = Array(castProfiles.map(\.name).referenceUniqued().prefix(15))
        let crewRows = embedded["crew"] as? [[String: Any]] ?? []
        let directors = crewRows.compactMap { row -> String? in
            guard string(row["type"])?.localizedCaseInsensitiveContains("director") == true,
                  let person = row["person"] as? [String: Any] else { return nil }
            return string(person["name"])
        }.referenceUniqued()
        let network = show["network"] as? [String: Any]
        let webChannel = show["webChannel"] as? [String: Any]
        let networkCountry = (network?["country"] as? [String: Any]).flatMap { string($0["name"]) }
        let channelCountry = (webChannel?["country"] as? [String: Any]).flatMap { string($0["name"]) }
        let premiered = string(show["premiered"]) ?? string(show["ended"])
        let image = show["image"] as? [String: Any]
        let imageURL = string(image?["original"]) ?? string(image?["medium"])
        let rating = number(show["rating"] as? [String: Any], key: "average").map { String(format: "%.1f", $0) }
        let runtime = number(show, key: "averageRuntime") ?? number(show, key: "runtime")
        let sourceURL = string(show["url"]).flatMap(URL.init(string:))
            ?? URL(string: "https://www.tvmaze.com")!

        return ReferenceTitleMetadata(
            synopsis: cleanHTML(string(show["summary"])),
            posterURL: imageURL.flatMap(URL.init(string:)),
            year: premiered.flatMap { String($0.prefix(4)).referenceNonEmpty },
            rating: rating,
            runtime: runtime.map { "\(Int($0.rounded())) min" },
            genres: (show["genres"] as? [String] ?? []).referenceUniqued(),
            country: networkCountry ?? channelCountry,
            director: directors.first,
            cast: cast,
            citations: [MetadataCitation(provider: "TVmaze", url: sourceURL)],
            attemptedProviders: ["TVmaze"],
            fetchedAt: Date(),
            ratingSource: rating == nil ? nil : "TVmaze",
            castProfiles: castProfiles.isEmpty ? nil : castProfiles,
            tvmazeCastProfilesVersion: Self.tvmazeCastProfilesVersion
        )
    }

    private static func bestTVmazeShow(in payload: Any, item: MediaItem, imdbID: String?) -> [String: Any]? {
        let candidates: [[String: Any]]
        if let results = payload as? [[String: Any]] {
            candidates = results.compactMap { $0["show"] as? [String: Any] }
        } else if let show = payload as? [String: Any], string(show["name"]) != nil {
            candidates = [show]
        } else {
            return nil
        }
        let ranked = candidates.compactMap { show -> (show: [String: Any], score: Double, yearDistance: Int?)? in
            let name = string(show["name"])
            guard let name else { return nil }
            let externalIDs = show["externals"] as? [String: Any]
            let showIMDbID = string(externalIDs?["imdb"])
            let directIMDbMatch = imdbID != nil && showIMDbID == imdbID
            let normalizedName = MediaTitleMatching.normalize(name)
            let titleScore = ([item.title] + item.matchingTitles)
                .map { MediaTitleMatching.similarity(normalizedName, MediaTitleMatching.normalize($0)) }
                .max() ?? 0
            let premiered = string(show["premiered"]) ?? string(show["ended"])
            let candidateYear = premiered.flatMap { Int($0.prefix(4)) }
            let yearDistance = Int(item.year).flatMap { target in candidateYear.map { abs(target - $0) } }
            let yearMatches = yearDistance.map { $0 <= 4 } ?? true
            guard directIMDbMatch || (titleScore >= 0.84 && (yearMatches || titleScore >= 0.97)) else {
                return nil
            }
            return (show, directIMDbMatch ? 1.0 : titleScore, yearDistance)
        }
        guard let show = ranked.sorted(by: {
            if $0.score != $1.score { return $0.score > $1.score }
            return ($0.yearDistance ?? Int.max) < ($1.yearDistance ?? Int.max)
        }).first?.show else { return nil }
        return show
    }

    static func parseWikidata(_ payload: Any) -> ReferenceTitleMetadata? {
        guard let root = payload as? [String: Any],
              let results = root["results"] as? [String: Any],
              let rows = results["bindings"] as? [[String: Any]], !rows.isEmpty else { return nil }
        var synopsis: String?
        var year: String?
        var runtime: String?
        var posterURL: URL?
        var genres: [String] = []
        var countries: [String] = []
        var directors: [String] = []
        var cast: [String] = []
        var sourceURL: URL?
        for row in rows {
            if let item = binding(row, "item") {
                sourceURL = wikidataPage(for: item) ?? sourceURL
            }
            synopsis = synopsis ?? binding(row, "itemDescription")
            if let date = binding(row, "date"), year == nil {
                year = date.range(of: #"\d{4}"#, options: .regularExpression).map { String(date[$0]) }
            }
            if let rawRuntime = binding(row, "runtime"), runtime == nil,
               let minutes = Double(rawRuntime), minutes > 0, minutes < 10_000 {
                runtime = "\(Int(minutes.rounded())) min"
            }
            if let rawImage = binding(row, "image"), posterURL == nil {
                posterURL = URL(string: rawImage.replacingOccurrences(of: "http://", with: "https://"))
            }
            genres.appendIfUnique(binding(row, "genreLabel"))
            countries.appendIfUnique(binding(row, "countryLabel"))
            directors.appendIfUnique(binding(row, "directorLabel"))
            cast.appendIfUnique(binding(row, "actorLabel"))
        }
        guard let sourceURL else { return nil }
        return ReferenceTitleMetadata(
            synopsis: synopsis,
            posterURL: posterURL,
            year: year,
            rating: nil,
            runtime: runtime,
            genres: Array(genres.prefix(12)),
            country: countries.prefix(5).joined(separator: ", ").referenceNonEmpty,
            director: directors.prefix(5).joined(separator: ", ").referenceNonEmpty,
            cast: Array(cast.prefix(20)),
            citations: [MetadataCitation(provider: "Wikidata", url: sourceURL)],
            attemptedProviders: ["Wikidata"],
            fetchedAt: Date()
        )
    }

    static func parseWikidataSearch(_ payload: Any, item: MediaItem) -> String? {
        guard let root = payload as? [String: Any],
              let candidates = root["search"] as? [[String: Any]] else { return nil }
        let ranked = candidates.compactMap { candidate -> (id: String, score: Double, yearDistance: Int?)? in
            guard let id = string(candidate["id"]), id.range(of: #"^Q\d+$"#, options: .regularExpression) != nil,
                  let label = string(candidate["label"]), let description = string(candidate["description"]) else { return nil }
            let descriptionForType = description.lowercased()
            let isMovie = ["film", "movie", "motion picture"].contains { descriptionForType.contains($0) }
            let isSeries = ["television series", "tv series", "web series", "animated series", "anime series", "miniseries"]
                .contains { descriptionForType.contains($0) }
            guard (item.kind == "Movie" && isMovie) || (item.kind == "Series" && isSeries) else { return nil }
            let aliases = (candidate["aliases"] as? [[String: Any]])?.compactMap { string($0["value"]) }
                ?? candidate["aliases"] as? [String] ?? []
            let names = [label] + aliases
            let score = names.flatMap { name in
                ([item.title] + item.matchingTitles).map {
                    MediaTitleMatching.similarity(MediaTitleMatching.normalize(name), MediaTitleMatching.normalize($0))
                }
            }.max() ?? 0
            guard score >= 0.95 else { return nil }
            let describedYear = description.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression)
                .flatMap { Int(description[$0]) }
            let yearDistance = Int(item.year).flatMap { target in describedYear.map { abs(target - $0) } }
            if let yearDistance, yearDistance > 3 { return nil }
            return (id, score, yearDistance)
        }
        return ranked.sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            return (left.yearDistance ?? Int.max) < (right.yearDistance ?? Int.max)
        }.first?.id
    }

    private static func fetchTVmaze(item: MediaItem, imdbID: String?) async -> ReferenceTitleMetadata? {
        guard item.kind == "Series" else { return nil }
        var queries = ([item.title] + item.matchingTitles).referenceUniqued().prefix(2)
        while let query = queries.first {
            queries = queries.dropFirst()
            guard let url = makeURL("https://api.tvmaze.com/search/shows", query: [URLQueryItem(name: "q", value: query)]) else { continue }
            if let payload = await getJSON(url, userAgent: "Denbox/1.0 (macOS media library; metadata lookup)"),
               let show = bestTVmazeShow(in: payload, item: item, imdbID: imdbID) {
                if let id = number(show, key: "id"), id > 0,
                   let detailURL = makeURL("https://api.tvmaze.com/shows/\(Int(id))", query: [
                    URLQueryItem(name: "embed[]", value: "cast"), URLQueryItem(name: "embed[]", value: "crew")
                   ]),
                   let details = await getJSON(detailURL, userAgent: "Denbox/1.0 (macOS media library; metadata lookup)"),
                   let metadata = parseTVmaze(details, item: item, imdbID: imdbID) {
                    return metadata
                }
                if let metadata = parseTVmaze(payload, item: item, imdbID: imdbID) { return metadata }
            }
        }
        return nil
    }

    private static func fetchWikidata(item: MediaItem, imdbID: String?) async -> ReferenceTitleMetadata? {
        if let imdbID, validIMDbID(imdbID),
           let matchedByIMDb = await queryWikidata(selector: "?item wdt:P345 \"\(imdbID)\".") {
            return matchedByIMDb
        }
        guard let entityID = await searchWikidataEntity(for: item) else { return nil }
        return await queryWikidata(selector: "VALUES ?item { wd:\(entityID) }")
    }

    private static func searchWikidataEntity(for item: MediaItem) async -> String? {
        for title in ([item.title] + item.matchingTitles).referenceUniqued().prefix(2) {
            guard let url = makeURL("https://www.wikidata.org/w/api.php", query: [
                URLQueryItem(name: "action", value: "wbsearchentities"),
                URLQueryItem(name: "search", value: title),
                URLQueryItem(name: "language", value: "en"),
                URLQueryItem(name: "type", value: "item"),
                URLQueryItem(name: "limit", value: "8"),
                URLQueryItem(name: "format", value: "json")
            ]),
            let payload = await getJSON(url, userAgent: "Denbox/1.0 (macOS media library; metadata lookup)"),
            let id = parseWikidataSearch(payload, item: item) else { continue }
            return id
        }
        return nil
    }

    private static func queryWikidata(selector: String) async -> ReferenceTitleMetadata? {
        let query = """
        SELECT ?item ?itemLabel ?itemDescription ?date ?runtime ?genreLabel ?countryLabel ?directorLabel ?actorLabel ?image WHERE {
          \(selector)
          OPTIONAL { ?item wdt:P577 ?date. }
          OPTIONAL { ?item wdt:P2047 ?runtime. }
          OPTIONAL { ?item wdt:P136 ?genre. }
          OPTIONAL { ?item wdt:P495 ?country. }
          OPTIONAL { ?item wdt:P57 ?director. }
          OPTIONAL { ?item wdt:P161 ?actor. }
          OPTIONAL { ?item wdt:P18 ?image. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language \"fa,en\". }
        }
        LIMIT 80
        """
        guard let url = makeURL("https://query.wikidata.org/sparql", query: [
            URLQueryItem(name: "query", value: query), URLQueryItem(name: "format", value: "json")
        ]) else { return nil }
        guard let payload = await getJSON(url, accept: "application/sparql-results+json", userAgent: "Denbox/1.0 (macOS media library; metadata lookup)") else { return nil }
        return parseWikidata(payload)
    }

    private static func validIMDbID(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: #"^tt\d{7,10}$"#, options: .regularExpression) != nil
    }

    private static func sourcePriority(_ metadata: ReferenceTitleMetadata) -> Int {
        switch metadata.citations.first?.provider {
        case "TMDB": 0
        case "TVmaze": 1
        case "Wikidata": 2
        default: 3
        }
    }

    private static func makeURL(_ raw: String, query: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        components.queryItems = query
        return components.url
    }

    private static func getJSON(_ url: URL, accept: String = "application/json", userAgent: String) async -> Any? {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 12)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else { return nil }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).referenceNonEmpty
    }

    private static func number(_ object: [String: Any]?, key: String) -> Double? {
        guard let value = object?[key], !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func binding(_ row: [String: Any], _ name: String) -> String? {
        string((row[name] as? [String: Any])?["value"])
    }

    private static func wikidataPage(for itemURL: String) -> URL? {
        guard let id = itemURL.split(separator: "/").last, id.hasPrefix("Q") else { return URL(string: itemURL) }
        return URL(string: "https://www.wikidata.org/wiki/\(id)")
    }

    private static func cleanHTML(_ value: String?) -> String? {
        guard let value else { return nil }
        let withoutTags = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")]
        let decoded = entities.reduce(withoutTags) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        return decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ").referenceNonEmpty
    }
}

private extension String {
    var referenceNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element: Hashable {
    func referenceUniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }

    mutating func appendIfUnique(_ value: Element?) {
        guard let value, !contains(value) else { return }
        append(value)
    }
}
