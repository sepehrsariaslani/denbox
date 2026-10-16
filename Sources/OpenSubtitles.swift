import Foundation

struct OnlineSubtitleFile: Decodable, Identifiable {
    let fileID: Int
    let fileName: String?

    var id: Int { fileID }

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case fileName = "file_name"
    }
}

struct OnlineSubtitleResult: Decodable, Identifiable {
    struct Attributes: Decodable {
        let language: String?
        let release: String?
        let downloadCount: Int?
        let movieHashMatch: Bool?
        let files: [OnlineSubtitleFile]

        enum CodingKeys: String, CodingKey {
            case language, release, files
            case downloadCount = "download_count"
            case movieHashMatch = "moviehash_match"
        }
    }

    let id: String
    let attributes: Attributes
}

enum OnlineSubtitleError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case serviceRejectedKey
    case rateLimited
    case serverStatus(Int)
    case noDownloadableFile
    case unsafeDownloadLink
    case tooLarge
    case emptySubtitle

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an OpenSubtitles API key in Denbox Settings first."
        case .invalidResponse: "OpenSubtitles returned an unreadable response."
        case .serviceRejectedKey: "OpenSubtitles rejected the API key. Check the key in Settings."
        case .rateLimited: "OpenSubtitles is rate limiting requests. Wait a moment and try again."
        case .serverStatus(let status): "OpenSubtitles request failed (HTTP \(status))."
        case .noDownloadableFile: "This subtitle result has no downloadable file."
        case .unsafeDownloadLink: "OpenSubtitles returned a download link that is not secure."
        case .tooLarge: "The subtitle file is larger than Denbox allows."
        case .emptySubtitle: "The downloaded subtitle file is empty."
        }
    }
}

struct OpenSubtitlesClient {
    private static let apiRoot = URL(string: "https://api.opensubtitles.com/api/v1")!
    private static let maxSubtitleBytes = 10 * 1_024 * 1_024
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search(
        query: String,
        videoURL: URL,
        language: String
    ) async throws -> [OnlineSubtitleResult] {
        guard !apiKey.isEmpty else { throw OnlineSubtitleError.missingAPIKey }
        var values = ["languages": language.lowercased()]
        let normalizedQuery = Self.normalizeQuery(query)
        if !normalizedQuery.isEmpty { values["query"] = normalizedQuery }
        if videoURL.isFileURL, let hash = try? Self.movieHash(for: videoURL) {
            values["moviehash"] = hash
        }
        guard normalizedQuery.count > 1 || values["moviehash"] != nil else { return [] }

        var components = URLComponents(url: Self.apiRoot.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)
        components?.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw OnlineSubtitleError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await Self.send(request)
        guard let payload = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            throw OnlineSubtitleError.invalidResponse
        }
        return payload.data
    }

    func download(_ result: OnlineSubtitleResult, forTitle title: String) async throws -> URL {
        guard !apiKey.isEmpty else { throw OnlineSubtitleError.missingAPIKey }
        guard let file = result.attributes.files.first else { throw OnlineSubtitleError.noDownloadableFile }

        var request = URLRequest(url: Self.apiRoot.appendingPathComponent("download"))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(DownloadRequest(fileID: file.fileID, subFormat: "srt"))
        let responseData = try await Self.send(request)
        guard let download = try? JSONDecoder().decode(DownloadResponse.self, from: responseData),
              let url = URL(string: download.link), url.scheme?.lowercased() == "https" else {
            throw OnlineSubtitleError.unsafeDownloadLink
        }

        var fileRequest = URLRequest(url: url)
        fileRequest.timeoutInterval = 45
        fileRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (contents, response) = try await Self.session.data(for: fileRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OnlineSubtitleError.invalidResponse
        }
        guard !contents.isEmpty else { throw OnlineSubtitleError.emptySubtitle }
        guard contents.count <= Self.maxSubtitleBytes else { throw OnlineSubtitleError.tooLarge }

        let directory = try Self.subtitleDirectory()
        let language = (result.attributes.language ?? "und").lowercased()
        let safeTitle = Self.safeFileComponent(title)
        let safeID = Self.safeFileComponent(result.id)
        let baseName = [safeTitle, language, safeID].filter { !$0.isEmpty }.joined(separator: ".")
        let destination = Self.uniqueURL(in: directory, baseName: baseName.isEmpty ? "subtitle" : baseName)
        try contents.write(to: destination, options: .atomic)
        return destination
    }

    static func movieHash(for url: URL) throws -> String? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
              fileSize >= 128 * 1_024 else { return nil }

        let chunkSize = 64 * 1_024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hash = fileSize
        for offset in [UInt64(0), fileSize - UInt64(chunkSize)] {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: chunkSize), data.count == chunkSize else { return nil }
            let bytes = [UInt8](data)
            for index in stride(from: 0, to: bytes.count, by: 8) {
                var word: UInt64 = 0
                for byteIndex in 0..<8 {
                    word |= UInt64(bytes[index + byteIndex]) << UInt64(byteIndex * 8)
                }
                hash &+= word
            }
        }
        return String(format: "%016llx", hash)
    }

    static func normalizeQuery(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.7"
        return "Denbox v\(version)"
    }

    private static func send(_ request: URLRequest, retries: Int = 1) async throws -> Data {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineSubtitleError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw OnlineSubtitleError.serviceRejectedKey }
        if http.statusCode == 429, retries > 0 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return try await send(request, retries: retries - 1)
        }
        if http.statusCode == 429 { throw OnlineSubtitleError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw OnlineSubtitleError.serverStatus(http.statusCode) }
        return data
    }

    private static func subtitleDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = root.appendingPathComponent("Denbox/Subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
    }

    private static func uniqueURL(in directory: URL, baseName: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).srt")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).srt")
            suffix += 1
        }
        return candidate
    }

    private struct SearchResponse: Decodable {
        let data: [OnlineSubtitleResult]
    }

    private struct DownloadRequest: Encodable {
        let fileID: Int
        let subFormat: String
        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case subFormat = "sub_format"
        }
    }

    private struct DownloadResponse: Decodable {
        let link: String
    }
}
