import Foundation

enum DiscoveryFeedError: LocalizedError, Equatable {
    case requestFailed(String)
    case noTMDBToken

    var errorDescription: String? {
        switch self {
        case .requestFailed(let source): "Could not load the \(source) feed. Try again later."
        case .noTMDBToken: "Add a TMDB Read Access Token in Settings to load today's popular titles."
        }
    }
}

enum DiscoveryCalendarKind: String, Sendable {
    case movieRelease
    case episode
}

struct DiscoveryCalendarEvent: Identifiable, Sendable {
    let id: String
    let date: Date
    let title: IMDbTitleMetadata
    let kind: DiscoveryCalendarKind
    let episodeTitle: String?
    let season: Int?
    let episode: Int?
    let airingDays: [String]
    let airtime: String?
    let timeZone: String?
    let channel: String?
}

struct BoxOfficeRecord: Identifiable, Sendable {
    let rank: Int
    let title: IMDbTitleMetadata
    let worldwideGross: String

    var id: String { title.id }
}

struct TrendingTitle: Identifiable, Sendable {
    let metadata: IMDbTitleMetadata
    let posterURL: URL?

    var id: String { metadata.id }
}

struct DiscoveryCalendarResult: Sendable {
    let events: [DiscoveryCalendarEvent]
    let sourceMessages: [String]
}

actor DiscoveryFeedService {
    static let shared = DiscoveryFeedService()

    private var boxOfficeCache: (date: Date, entries: [BoxOfficeRecord])?
    private var popularCache: [String: (date: Date, titles: [TrendingTitle])] = [:]
    private var releaseCache: [String: [DiscoveryCalendarEvent]] = [:]
    private var tvmazeCache: (date: Date, episodes: [TVMazeEpisode])?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    func popularToday(kind: String, accessToken: String?, force: Bool = false) async throws -> [TrendingTitle] {
        guard let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw DiscoveryFeedError.noTMDBToken
        }
        let mediaType = kind == "Series" ? "tv" : "movie"
        if !force, let cache = popularCache[mediaType], Date().timeIntervalSince(cache.date) < 6 * 60 * 60 {
            return cache.titles
        }
        var components = URLComponents(string: "https://api.themoviedb.org/3/trending/\(mediaType)/day")!
        components.queryItems = [URLQueryItem(name: "language", value: "en-US")]
        guard let url = components.url else { throw DiscoveryFeedError.requestFailed("TMDB") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Denbox/1.0 (macOS media library; discovery)", forHTTPHeaderField: "User-Agent")
        let data = try await successfulData(for: request, source: "TMDB")
        guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = payload["results"] as? [[String: Any]] else {
            throw DiscoveryFeedError.requestFailed("TMDB")
        }
        let titles: [TrendingTitle] = results.compactMap { row -> TrendingTitle? in
            guard let rawID = row["id"], let tmdbID = Int(String(describing: rawID)) else { return nil }
            let title = (row["title"] as? String) ?? (row["name"] as? String) ?? ""
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let dateText = (row["release_date"] as? String) ?? (row["first_air_date"] as? String)
            let year = dateText.flatMap { Int($0.prefix(4)) }
            let rating = (row["vote_average"] as? NSNumber)?.doubleValue
            let votes = (row["vote_count"] as? NSNumber)?.intValue
            let metadata = IMDbTitleMetadata(tconst: "tmdb-\(mediaType)-\(tmdbID)", title: title, year: year,
                                             genres: [], rating: rating, votes: votes, kind: kind)
            let posterPath = row["poster_path"] as? String
            let posterURL = posterPath.flatMap { path in
                path.hasPrefix("/") && !path.contains("..")
                    ? URL(string: "https://image.tmdb.org/t/p/w342\(path)") : nil
            }
            return TrendingTitle(metadata: metadata, posterURL: posterURL)
        }
        guard !titles.isEmpty else { throw DiscoveryFeedError.requestFailed("TMDB") }
        popularCache[mediaType] = (Date(), titles)
        return titles
    }

    func boxOffice(force: Bool = false) async throws -> [BoxOfficeRecord] {
        if !force, let cache = boxOfficeCache, Date().timeIntervalSince(cache.date) < 4 * 60 * 60 {
            return cache.entries
        }
        let url = URL(string: "https://www.boxofficemojo.com/chart/ww_top_lifetime_gross/?area=XWW")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let data = try await successfulData(for: request, source: "Box Office Mojo")
        let entries = Self.parseBoxOfficeHTML(String(decoding: data, as: UTF8.self))
        guard !entries.isEmpty else { throw DiscoveryFeedError.requestFailed("Box Office Mojo") }
        boxOfficeCache = (Date(), entries)
        return entries
    }

    func releaseCalendar(cacheKey: String, startDate: Date, endDate: Date,
                         releaseMonths: [String], force: Bool = false) async -> DiscoveryCalendarResult {
        let key = cacheKey
        if !force, let cached = releaseCache[key] {
            return DiscoveryCalendarResult(events: cached, sourceMessages: [])
        }

        async let episodesTask = fetchTVMazeEpisodes()
        var events: [DiscoveryCalendarEvent] = []
        var messages: [String] = []
        var releaseCalendarFailed = false
        for releaseMonth in releaseMonths {
            let parts = releaseMonth.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            switch await fetchMovieReleases(year: parts[0], month: parts[1]) {
            case .success(let rows): events.append(contentsOf: rows)
            case .failure: releaseCalendarFailed = true
            }
        }
        let episodesResult = await episodesTask
        if releaseCalendarFailed { messages.append("Some movie release dates from Box Office Mojo could not be loaded.") }
        switch episodesResult {
        case .success(let episodes): events.append(contentsOf: episodes.filter { Self.isWithinRange($0.date, startDate: startDate, endDate: endDate) })
        case .failure: messages.append("TV episode schedules from TVmaze could not be loaded.")
        }

        let sorted = events.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.kind != rhs.kind { return lhs.kind == .movieRelease }
            return lhs.title.title.localizedCaseInsensitiveCompare(rhs.title.title) == .orderedAscending
        }
        if !sorted.isEmpty { releaseCache[key] = sorted }
        return DiscoveryCalendarResult(events: sorted, sourceMessages: messages)
    }

    private func fetchMovieReleases(year: Int, month: Int) async -> Result<[DiscoveryCalendarEvent], Error> {
        do {
            let url = URL(string: "https://www.boxofficemojo.com/calendar/?ref_=bo_nb_hm_tab&yr=\(year)&month=\(month)")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            let data = try await successfulData(for: request, source: "Box Office Mojo")
            let events = Self.parseMovieReleases(String(decoding: data, as: UTF8.self), year: year, month: month)
            guard !events.isEmpty else { throw DiscoveryFeedError.requestFailed("Box Office Mojo release calendar") }
            return .success(events)
        } catch {
            return .failure(error)
        }
    }

    private func fetchTVMazeEpisodes() async -> Result<[DiscoveryCalendarEvent], Error> {
        do {
            let episodes: [TVMazeEpisode]
            if let cache = tvmazeCache, Date().timeIntervalSince(cache.date) < 24 * 60 * 60 {
                episodes = cache.episodes
            } else if let disk = Self.readTVmazeCache(), Date().timeIntervalSince(disk.date) < 24 * 60 * 60 {
                episodes = disk.episodes
                tvmazeCache = (disk.date, episodes)
            } else {
                let url = URL(string: "https://api.tvmaze.com/schedule/full")!
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("Denbox/1.0 (macOS media library; TV schedule)", forHTTPHeaderField: "User-Agent")
                let data: Data
                do {
                    data = try await successfulData(for: request, source: "TVmaze")
                } catch {
                    if let stale = Self.readTVmazeCache() {
                        episodes = stale.episodes
                        tvmazeCache = (stale.date, episodes)
                        return .success(Self.calendarEvents(from: episodes))
                    }
                    throw error
                }
                guard let decoded = try? JSONDecoder().decode([TVMazeEpisode].self, from: data) else {
                    throw DiscoveryFeedError.requestFailed("TVmaze")
                }
                episodes = decoded
                tvmazeCache = (Date(), episodes)
                Self.writeTVmazeCache(data)
            }
            return .success(Self.calendarEvents(from: episodes))
        } catch {
            return .failure(error)
        }
    }

    private func successfulData(for request: URLRequest, source: String) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !data.isEmpty else { throw DiscoveryFeedError.requestFailed(source) }
            return data
        } catch let error as DiscoveryFeedError {
            throw error
        } catch {
            throw DiscoveryFeedError.requestFailed(source)
        }
    }

    private static func parseBoxOfficeHTML(_ html: String) -> [BoxOfficeRecord] {
        let rows = matches(in: html, pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#)
        return rows.compactMap { row -> BoxOfficeRecord? in
            guard row.count >= 2 else { return nil }
            let rowBody = row[1]
            guard let titleMatch = firstMatch(in: rowBody, pattern: #"(?is)href="/title/(tt\d+)/[^\"]*"[^>]*>(.*?)</a>"#),
                  titleMatch.count >= 3 else { return nil }
            let cells = matches(in: rowBody, pattern: #"(?is)<td\b[^>]*>(.*?)</td>"#)
            guard cells.count >= 8 else { return nil }
            let rank = Int(plainText(cells[0].last ?? "")) ?? 0
            let gross = plainText(cells[2].last ?? "")
            let year = Int(plainText(cells[7].last ?? ""))
            let title = plainText(titleMatch[2])
            guard rank > 0, !title.isEmpty, gross.hasPrefix("$") else { return nil }
            let metadata = IMDbTitleMetadata(tconst: titleMatch[1], title: title, year: year,
                                             genres: [], rating: nil, votes: nil, kind: "Movie")
            return BoxOfficeRecord(rank: rank, title: metadata, worldwideGross: gross)
        }
    }

    private static func parseMovieReleases(_ html: String, year: Int, month: Int) -> [DiscoveryCalendarEvent] {
        let rows = matches(in: html, pattern: #"(?is)<tr\b([^>]*)>(.*?)</tr>"#)
        let groupDate = DateFormatter()
        groupDate.locale = Locale(identifier: "en_US_POSIX")
        groupDate.calendar = Calendar(identifier: .gregorian)
        groupDate.dateFormat = "MMMM d, yyyy"
        var currentDate: Date?
        var output: [DiscoveryCalendarEvent] = []
        for row in rows where row.count >= 3 {
            let attributes = row[1]
            let body = row[2]
            if attributes.localizedCaseInsensitiveContains("mojo-group-label") {
                let label = plainText(body)
                currentDate = groupDate.date(from: label)
                continue
            }
            guard let date = currentDate,
                  let titleMatch = firstMatch(in: body, pattern: #"(?is)<h3\b[^>]*>(.*?)</h3>"#),
                  let title = titleMatch.first.map(plainText), !title.isEmpty,
                  Calendar(identifier: .gregorian).component(.year, from: date) == year,
                  Calendar(identifier: .gregorian).component(.month, from: date) == month else { continue }
            let dayStamp = ISO8601DateFormatter().string(from: date)
            let slug = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init).joined(separator: "-")
            let metadata = IMDbTitleMetadata(tconst: "bom-release-\(dayStamp)-\(slug)", title: title,
                                             year: year, genres: [], rating: nil, votes: nil, kind: "Movie")
            output.append(DiscoveryCalendarEvent(id: metadata.id, date: date, title: metadata, kind: .movieRelease,
                                                episodeTitle: nil, season: nil, episode: nil, airingDays: [],
                                                airtime: nil, timeZone: nil, channel: nil))
        }
        return output
    }

    private static func calendarEvents(from episodes: [TVMazeEpisode]) -> [DiscoveryCalendarEvent] {
        episodes.compactMap { episode in
            guard let airdate = episode.airdate, let date = localDate(fromISODate: airdate),
                  let show = episode.embedded?.show, !show.name.isEmpty else { return nil }
            let imdbID = show.externals?.imdb.flatMap { $0.hasPrefix("tt") ? $0 : nil }
            let showYear = show.premiered.flatMap { Int($0.prefix(4)) }
            let stableID = imdbID ?? "tvmaze-show-\(show.id)"
            let metadata = IMDbTitleMetadata(tconst: stableID, title: show.name, year: showYear,
                                             genres: show.genres ?? [], rating: nil, votes: nil, kind: "Series")
            return DiscoveryCalendarEvent(
                id: "tvmaze-episode-\(episode.id)", date: date, title: metadata, kind: .episode,
                episodeTitle: episode.name, season: episode.season, episode: episode.number,
                airingDays: show.schedule?.days ?? [], airtime: nonempty(show.schedule?.time),
                timeZone: nonempty(show.webChannel?.country?.timezone ?? show.network?.country?.timezone),
                channel: nonempty(show.webChannel?.name ?? show.network?.name)
            )
        }
    }

    private static func isWithinRange(_ date: Date, startDate: Date, endDate: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: startDate) && day <= calendar.startOfDay(for: endDate)
    }

    private static func localDate(fromISODate value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func matches(in value: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: value) else { return "" }
                return String(value[range])
            }
        }
    }

    private static func firstMatch(in value: String, pattern: String) -> [String]? {
        matches(in: value, pattern: pattern).first
    }

    private static func plainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        let named: [(String, String)] = [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">")]
        return named.reduce(noTags) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            .replacingOccurrences(of: #"&#(\d+);"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readTVmazeCache() -> (date: Date, episodes: [TVMazeEpisode])? {
        guard let file = tvmazeCacheURL(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              let data = try? Data(contentsOf: file),
              let episodes = try? JSONDecoder().decode([TVMazeEpisode].self, from: data) else { return nil }
        return (modified, episodes)
    }

    private static func writeTVmazeCache(_ data: Data) {
        guard let file = tvmazeCacheURL() else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func tvmazeCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Denbox", isDirectory: true)
            .appendingPathComponent("tvmaze-schedule-full.json")
    }
}

private struct TVMazeEpisode: Decodable, Sendable {
    let id: Int
    let name: String
    let season: Int?
    let number: Int?
    let airdate: String?
    let embedded: Embedded?

    enum CodingKeys: String, CodingKey {
        case id, name, season, number, airdate
        case embedded = "_embedded"
    }

    struct Embedded: Decodable, Sendable { let show: Show? }
    struct Show: Decodable, Sendable {
        let id: Int
        let name: String
        let premiered: String?
        let genres: [String]?
        let schedule: Schedule?
        let externals: Externals?
        let network: Channel?
        let webChannel: Channel?

        enum CodingKeys: String, CodingKey {
            case id, name, premiered, genres, schedule, externals, network
            case webChannel = "webChannel"
        }
    }
    struct Schedule: Decodable, Sendable { let time: String?; let days: [String]? }
    struct Externals: Decodable, Sendable { let imdb: String? }
    struct Channel: Decodable, Sendable { let name: String?; let country: Country? }
    struct Country: Decodable, Sendable { let timezone: String? }
}
