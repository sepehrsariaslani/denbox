import Foundation
import MPV

@main
struct DenboxLiveAPITests {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--cached-player-probe") {
            try await probeCachedPlayerSources()
            return
        }

        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DenboxLiveCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let model = LibraryModel(
            loadRemoteCatalog: false,
            databaseURL: testDirectory.appendingPathComponent("library.sqlite")
        )
        try await Task.sleep(nanoseconds: 250_000_000)
        await model.refreshCatalog()
        for _ in 0..<300 where model.isConnecting
            || model.items.filter({ $0.kind == "Movie" }).count < 30
            || model.items.filter({ $0.kind == "Series" }).count < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let initialMovieCount = model.items.filter { $0.kind == "Movie" }.count
        let initialSeriesCount = model.items.filter { $0.kind == "Series" }.count
        try require(initialMovieCount >= 20 && initialSeriesCount >= 20,
                    "live catalog did not populate both media categories (\(initialMovieCount) movies, \(initialSeriesCount) series, status: \(model.connectionStatus))")
        try require(initialMovieCount + initialSeriesCount >= 50,
                    "live catalog did not retain the unique titles from both initial API pages")

        guard let movie = model.items.first(where: { $0.kind == "Movie" && $0.isRemote }),
              let series = model.items.first(where: { $0.kind == "Series" && $0.isRemote }) else {
            throw TestFailure(message: "live catalog did not provide both media types")
        }
        guard let movieDetails = await model.loadDetails(for: movie, forceRefresh: true),
              !movieDetails.sources.isEmpty || !movieDetails.downloadSources.isEmpty else {
            throw TestFailure(message: "live movie detail has no playable/download URL")
        }
        guard let seriesDetails = await model.loadDetails(for: series, forceRefresh: true),
              let episode = seriesDetails.seasons.flatMap(\.episodes).first,
              !episode.sources.isEmpty || !episode.downloadSources.isEmpty else {
            throw TestFailure(message: "live series detail has no episode playback/download URL")
        }

        let movieLinkCount = max(movieDetails.sources.count, movieDetails.downloadSources.count)
        let episodeLinkCount = max(episode.sources.count, episode.downloadSources.count)
        let moviePlaybackSource = movieDetails.sources.first ?? movieDetails.downloadSources.first!
        let episodePlaybackSource = episode.sources.first ?? episode.downloadSources.first!
        if CommandLine.arguments.contains("--catalog-only") {
            print("PASS live catalog: \(initialMovieCount) movies, \(initialSeriesCount) series")
            print("PASS live details: movie links=\(movieLinkCount), episode links=\(episodeLinkCount)")
            return
        }
        if CommandLine.arguments.contains("--mpv-probe-only") {
            try probeMPV(moviePlaybackSource, label: "movie")
            try probeMPV(episodePlaybackSource, label: "episode")
            print("PASS embedded mpv: movie and episode sources opened with their API headers")
            return
        }
        let directSource = movieDetails.downloadSources.first ?? movieDetails.sources[0]
        let firstRange = try await probeRange(directSource, range: "bytes=0-0")
        let secondRange = try await probeRange(directSource, range: "bytes=1-1")
        try require(firstRange.status == 206 && secondRange.status == 206
                    && firstRange.totalBytes == secondRange.totalBytes,
                    "live media server did not honor arbitrary HTTP byte ranges")
        let livePartCount = min(8, max(2, Int((firstRange.totalBytes + 4_194_303) / 4_194_304)))

        if CommandLine.arguments.contains("--mpv-probe") {
            try probeMPV(moviePlaybackSource, label: "movie")
            try probeMPV(episodePlaybackSource, label: "episode")
            print("PASS embedded mpv: movie and episode sources opened with their API headers")
        }
        if CommandLine.arguments.contains("--playback-probe-only") {
            print("PASS live playback sources: movie links=\(movieLinkCount), episode links=\(episodeLinkCount)")
            return
        }
        let moviePlayback = await probeMediaResponse(moviePlaybackSource)
        let episodePlayback = await probeMediaResponse(episodePlaybackSource)
        print("Live movie stream: .\(moviePlaybackSource.url.pathExtension.lowercased()) · \(moviePlayback)")
        print("Live episode stream: .\(episodePlaybackSource.url.pathExtension.lowercased()) · \(episodePlayback)")

        model.section = .movies
        for _ in 0..<4 where model.items.filter({ $0.kind == "Movie" }).count == initialMovieCount {
            let previousStatus = model.connectionStatus
            model.loadMoreCatalog()
            for _ in 0..<300 where model.connectionStatus == previousStatus || model.isLoadingMore {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        let expandedMovieCount = model.items.filter { $0.kind == "Movie" }.count
        try require(expandedMovieCount > initialMovieCount, "live movie pagination did not append a later page")

        print("PASS live API: \(initialMovieCount) initial movies, \(initialSeriesCount) initial series")
        print("PASS live details: movie links=\(movieLinkCount), episode links=\(episodeLinkCount)")
        print("PASS live media source: arbitrary byte ranges accepted; planned parts=\(livePartCount)")
        print("PASS live pagination: movie titles grew to \(expandedMovieCount)")
    }

    @MainActor
    private static func probeCachedPlayerSources() async throws {
        let model = LibraryModel(loadRemoteCatalog: false, refreshStaleDetailsInBackground: false)
        let database = MediaDatabase()
        let itemsWithCachedDetails = database.loadCatalog().filter {
            $0.isRemote && database.loadDetailsPayload(for: $0.id) != nil
        }
        guard let movie = itemsWithCachedDetails.first(where: { $0.kind == "Movie" }),
              let series = itemsWithCachedDetails.first(where: { $0.kind == "Series" }) else {
            throw TestFailure(message: "the local database needs cached movie and series details before the AVPlayer probe")
        }
        guard let movieDetails = await model.loadDetails(for: movie),
              let movieSource = movieDetails.sources.first ?? movieDetails.downloadSources.first,
              let seriesDetails = await model.loadDetails(for: series),
              let episode = seriesDetails.seasons.flatMap(\.episodes).first,
              let episodeSource = episode.sources.first ?? episode.downloadSources.first else {
            throw TestFailure(message: "cached detail data did not contain movie and episode streams")
        }

        let movieResult = await probeMediaResponse(movieSource)
        let episodeResult = await probeMediaResponse(episodeSource)
        print("Cached movie stream: .\(movieSource.url.pathExtension.lowercased()) · \(movieResult)")
        print("Cached episode stream: .\(episodeSource.url.pathExtension.lowercased()) · \(episodeResult)")
    }

    private static func probeMediaResponse(_ source: MediaStreamSource) async -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source.url)
        request.setValue("bytes=0-63", forHTTPHeaderField: "Range")
        request.setValue("video/*,*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        for (name, value) in source.headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { return "non-HTTP response" }
            var iterator = bytes.makeAsyncIterator()
            var count = 0
            while count < 64, try await iterator.next() != nil { count += 1 }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown-type"
            let contentRange = http.value(forHTTPHeaderField: "Content-Range") ?? "no-range"
            return "HTTP \(http.statusCode) · \(contentType) · \(count) bytes · \(contentRange)"
        } catch {
            let failure = error as NSError
            return "request-error \(failure.domain)/\(failure.code)"
        }
    }

    private static func probeMPV(_ source: MediaStreamSource, label: String) throws {
        guard let handle = mpv_create() else {
            throw TestFailure(message: "libmpv could not create a playback context for the \(label)")
        }
        defer { mpv_terminate_destroy(handle) }

        let options = [
            ("config", "no"),
            ("vo", "null"),
            ("ao", "null"),
            ("terminal", "no"),
            ("msg-level", "all=no")
        ]
        for (name, value) in options {
            _ = name.withCString { key in value.withCString { mpv_set_option_string(handle, key, $0) } }
        }
        guard mpv_initialize(handle) >= 0 else {
            throw TestFailure(message: "libmpv could not initialize for the \(label)")
        }

        let headers = source.headers.sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }.map { "\($0.key): \($0.value)" }.joined(separator: ",")
        _ = "http-header-fields".withCString { key in headers.withCString { mpv_set_property_string(handle, key, $0) } }

        let arguments = ["loadfile", source.url.absoluteString, "replace"]
        let owned = arguments.map { strdup($0) }
        defer { owned.forEach { if let pointer = $0 { free(pointer) } } }
        var pointers: [UnsafePointer<CChar>?] = owned.map { pointer in
            guard let pointer else { return nil }
            return UnsafePointer<CChar>(pointer)
        }
        pointers.append(nil)
        let commandResult = pointers.withUnsafeMutableBufferPointer {
            mpv_command(handle, $0.baseAddress)
        }
        guard commandResult >= 0 else {
            throw TestFailure(message: "libmpv rejected the \(label) source command")
        }

        let deadline = Date().addingTimeInterval(20)
        var didLoad = false
        while Date() < deadline && !didLoad {
            guard let event = mpv_wait_event(handle, 0.25) else { continue }
            if event.pointee.event_id == MPV_EVENT_FILE_LOADED {
                didLoad = true
            } else if event.pointee.event_id == MPV_EVENT_END_FILE,
                      let details = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee,
                      details.reason == MPV_END_FILE_REASON_ERROR.rawValue {
                let reason = mpv_error_string(Int32(details.error)).map(String.init(cString:)) ?? "unknown error"
                throw TestFailure(message: "libmpv could not open the \(label) source (\(reason))")
            }
        }
        try require(didLoad, "libmpv did not finish opening the \(label) source within 20 seconds")
    }

    private static func probeRange(
        _ source: MediaStreamSource,
        range: String
    ) async throws -> (status: Int, totalBytes: Int64) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source.url)
        request.setValue(range, forHTTPHeaderField: "Range")
        for (name, value) in source.headers { request.setValue(value, forHTTPHeaderField: name) }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            let failure = error as NSError
            throw TestFailure(message: "range request failed (\(failure.domain)/\(failure.code))")
        }
        guard let http = response as? HTTPURLResponse else {
            throw TestFailure(message: "range probe returned a non-HTTP response")
        }
        var iterator = bytes.makeAsyncIterator()
        _ = try await iterator.next()
        let total = http.value(forHTTPHeaderField: "Content-Range")?
            .split(separator: "/").last.flatMap { Int64($0) } ?? 0
        return (http.statusCode, total)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
