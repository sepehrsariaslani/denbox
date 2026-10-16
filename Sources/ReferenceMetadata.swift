import Foundation

struct MetadataCitation: Codable, Equatable, Identifiable, Sendable {
    let provider: String
    let url: URL

    var id: String { provider }
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

    static func empty(fetchedAt: Date = Date()) -> Self {
        Self(synopsis: nil, posterURL: nil, year: nil, rating: nil, runtime: nil,
             genres: [], country: nil, director: nil, cast: [], citations: [], attemptedProviders: [], fetchedAt: fetchedAt)
    }

    var isEmpty: Bool {
        synopsis == nil && posterURL == nil && year == nil && rating == nil && runtime == nil
            && genres.isEmpty && country == nil && director == nil && cast.isEmpty && citations.isEmpty
    }

    func merging(_ fallback: Self) -> Self {
        let citationMap = Dictionary((citations + fallback.citations).map { ($0.provider, $0) },
                                     uniquingKeysWith: { first, _ in first })
        return Self(
            synopsis: synopsis ?? fallback.synopsis,
            posterURL: posterURL ?? fallback.posterURL,
            year: year ?? fallback.year,
            rating: rating ?? fallback.rating,
            runtime: runtime ?? fallback.runtime,
            genres: Array((genres + fallback.genres).uniqued().prefix(12)),
            country: country ?? fallback.country,
            director: director ?? fallback.director,
            cast: Array((cast + fallback.cast).uniqued().prefix(20)),
            citations: citationMap.values.sorted { $0.provider < $1.provider },
            attemptedProviders: Array(Set(attemptedProviders + fallback.attemptedProviders)).sorted(),
            fetchedAt: max(fetchedAt, fallback.fetchedAt)
        )
    }
}

enum ReferenceMetadataService {
    private static let cacheLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let emptyCacheLifetime: TimeInterval = 24 * 60 * 60

    static func shouldRefresh(_ cached: ReferenceTitleMetadata?, for item: MediaItem, imdbID: String?) -> Bool {
        guard let cached else { return true }
        let age = Date().timeIntervalSince(cached.fetchedAt)
        if age > (cached.isEmpty ? emptyCacheLifetime : cacheLifetime) { return true }
        let attempted = Set(cached.attemptedProviders)
        if item.kind == "Series", !attempted.contains("TVmaze") { return true }
        let wantsWikidata = item.kind == "Movie" || item.kind == "Series"
        if wantsWikidata {
            let hasWikidataResult = cached.citations.contains { $0.provider == "Wikidata" }
            if validIMDbID(imdbID), !hasWikidataResult { return true }
            if !attempted.contains("Wikidata") { return true }
        }
        return false
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
            cast: details.cast.isEmpty ? metadata.cast : details.cast,
            sources: details.sources,
            downloadSources: details.downloadSources,
            seasons: details.seasons,
            imdbID: details.imdbID,
            imdbRating: details.imdbRating,
            imdbVotes: details.imdbVotes,
            similarSeries: details.similarSeries
        )
    }

    static func fetch(for item: MediaItem, imdbID: String?, existing: ReferenceTitleMetadata?) async -> ReferenceTitleMetadata {
        let existingAge = existing.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity
        let stale = existingAge > ((existing?.isEmpty ?? true) ? emptyCacheLifetime : cacheLifetime)
        let attempted = Set(existing?.attemptedProviders ?? [])
        let wantsTVmaze = item.kind == "Series" && (stale || !attempted.contains("TVmaze"))
        let wantsWikidata = (item.kind == "Movie" || item.kind == "Series")
            && (stale || !attempted.contains("Wikidata"))
        guard wantsTVmaze || wantsWikidata else {
            var unchanged = existing ?? .empty()
            unchanged.fetchedAt = Date()
            return unchanged
        }

        let fetched: [ReferenceTitleMetadata?] = await withTaskGroup(of: ReferenceTitleMetadata?.self) { group in
            if wantsTVmaze { group.addTask { await fetchTVmaze(item: item, imdbID: imdbID) } }
            if wantsWikidata { group.addTask { await fetchWikidata(item: item, imdbID: imdbID) } }
            var values: [ReferenceTitleMetadata?] = []
            for await value in group { values.append(value) }
            return values
        }

        var result = existing ?? .empty()
        let orderedParts = fetched.compactMap({ $0 }).sorted { left, right in
            sourcePriority(left) < sourcePriority(right)
        }
        for part in orderedParts {
            result = result.merging(part)
        }
        if wantsTVmaze { result.attemptedProviders.appendIfUnique("TVmaze") }
        if wantsWikidata { result.attemptedProviders.appendIfUnique("Wikidata") }
        result.fetchedAt = Date()
        return result
    }

    static func parseTVmaze(_ payload: Any, item: MediaItem, imdbID: String?) -> ReferenceTitleMetadata? {
        guard item.kind == "Series", let show = bestTVmazeShow(in: payload, item: item, imdbID: imdbID) else { return nil }
        let embedded = show["_embedded"] as? [String: Any] ?? [:]
        let castRows = embedded["cast"] as? [[String: Any]] ?? []
        let cast = Array(castRows.compactMap { row in
            (row["person"] as? [String: Any]).flatMap { string($0["name"]) }
        }.uniqued().prefix(15))
        let crewRows = embedded["crew"] as? [[String: Any]] ?? []
        let directors = crewRows.compactMap { row -> String? in
            guard string(row["type"])?.localizedCaseInsensitiveContains("director") == true,
                  let person = row["person"] as? [String: Any] else { return nil }
            return string(person["name"])
        }.uniqued()
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
            genres: (show["genres"] as? [String] ?? []).uniqued(),
            country: networkCountry ?? channelCountry,
            director: directors.first,
            cast: cast,
            citations: [MetadataCitation(provider: "TVmaze", url: sourceURL)],
            attemptedProviders: ["TVmaze"],
            fetchedAt: Date()
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
        var queries = ([item.title] + item.matchingTitles).uniqued().prefix(2)
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
        for title in ([item.title] + item.matchingTitles).uniqued().prefix(2) {
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
        metadata.citations.first?.provider == "TVmaze" ? 0 : 1
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
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }

    mutating func appendIfUnique(_ value: Element?) {
        guard let value, !contains(value) else { return }
        append(value)
    }
}
