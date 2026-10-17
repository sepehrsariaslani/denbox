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

struct AssrtSubtitle: Decodable, Identifiable {
    struct Language: Decodable {
        let description: String?

        enum CodingKeys: String, CodingKey {
            case description = "desc"
        }
    }

    let id: Int
    let nativeName: String?
    let videoName: String?
    let subtype: String?
    let uploadTime: String?
    let voteScore: Int?
    let releaseSite: String?
    let language: Language?

    var stableID: String { "assrt-\(id)" }

    enum CodingKeys: String, CodingKey {
        case id, subtype, language = "lang"
        case nativeName = "native_name"
        case videoName = "videoname"
        case uploadTime = "upload_time"
        case voteScore = "vote_score"
        case releaseSite = "release_site"
    }
}

enum AssrtSubtitleError: LocalizedError {
    case missingToken
    case invalidToken
    case invalidResponse
    case queryTooShort
    case rateLimited
    case serviceStatus(Int)
    case noDirectSubtitleFile
    case unsafeDownloadLink
    case serverStatus(Int)
    case tooLarge
    case emptySubtitle

    var errorDescription: String? {
        switch self {
        case .missingToken: "Add your ASSRT API token in Denbox Settings first."
        case .invalidToken: "ASSRT rejected the API token. Check the token in Settings."
        case .invalidResponse: "ASSRT returned an unreadable response."
        case .queryTooShort: "ASSRT search needs at least four characters."
        case .rateLimited: "ASSRT is rate limiting requests. Wait a moment and try again."
        case .serviceStatus(let status): "ASSRT request failed (code \(status))."
        case .noDirectSubtitleFile: "This ASSRT result has no direct subtitle text file."
        case .unsafeDownloadLink: "ASSRT returned an unsupported subtitle download link."
        case .serverStatus(let status): "ASSRT request failed (HTTP \(status))."
        case .tooLarge: "The subtitle file is larger than Denbox allows."
        case .emptySubtitle: "The downloaded subtitle file is empty."
        }
    }
}

struct AssrtSubtitleClient {
    private static let apiRoot = URL(string: "https://api.assrt.net/v1")!
    private static let maxSubtitleBytes = 10 * 1_024 * 1_024
    private static let supportedSubtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub"]
    private static let redirectDelegate = AssrtRedirectPolicy()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
    }()
    private let token: String

    init(token: String) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search(query: String, videoURL: URL) async throws -> [AssrtSubtitle] {
        guard !token.isEmpty else { throw AssrtSubtitleError.missingToken }
        let normalizedQuery = Self.normalizeQuery(query)
        guard normalizedQuery.count >= 4 else { throw AssrtSubtitleError.queryTooShort }

        var components = URLComponents(url: Self.apiRoot.appendingPathComponent("sub/search"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "q", value: normalizedQuery),
            URLQueryItem(name: "cnt", value: "15"),
            URLQueryItem(name: "pos", value: "0")
        ]
        let originalFileName = videoURL.isFileURL ? videoURL.deletingPathExtension().lastPathComponent : nil
        if let originalFileName, Self.normalizeQuery(originalFileName) == normalizedQuery {
            queryItems.append(URLQueryItem(name: "is_file", value: "1"))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw AssrtSubtitleError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await Self.send(request)
        return try Self.decodeSearchResponse(data)
    }

    func download(_ result: AssrtSubtitle, forTitle title: String) async throws -> URL {
        guard !token.isEmpty else { throw AssrtSubtitleError.missingToken }
        var components = URLComponents(url: Self.apiRoot.appendingPathComponent("sub/detail"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: String(result.id))]
        guard let url = components?.url else { throw AssrtSubtitleError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let detailData = try await Self.send(request)
        let subtitleFile = try Self.decodeDetailResponse(detailData)
        let fileURL = try Self.validatedSubtitleURL(subtitleFile.url)

        var fileRequest = URLRequest(url: fileURL)
        fileRequest.timeoutInterval = 45
        fileRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (contents, response) = try await Self.session.data(for: fileRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AssrtSubtitleError.invalidResponse
        }
        guard !contents.isEmpty else { throw AssrtSubtitleError.emptySubtitle }
        guard contents.count <= Self.maxSubtitleBytes else { throw AssrtSubtitleError.tooLarge }

        let directory = try Self.subtitleDirectory()
        let safeTitle = Self.safeFileComponent(title)
        let safeFileName = Self.safeFileComponent(subtitleFile.fileName)
        let fileExtension = URL(fileURLWithPath: subtitleFile.fileName).pathExtension.lowercased()
        guard Self.supportedSubtitleExtensions.contains(fileExtension) else {
            throw AssrtSubtitleError.noDirectSubtitleFile
        }
        let baseName = [safeTitle, "assrt", String(result.id), safeFileName]
            .filter { !$0.isEmpty }
            .joined(separator: ".")
        let destination = Self.uniqueURL(
            in: directory,
            baseName: baseName.isEmpty ? "subtitle-assrt-\(result.id)" : baseName,
            extension: fileExtension
        )
        try contents.write(to: destination, options: .atomic)
        return destination
    }

    static func normalizeQuery(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func decodeSearchResponse(_ data: Data) throws -> [AssrtSubtitle] {
        let envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
        try checkStatus(envelope.status)
        return envelope.sub?.subs ?? []
    }

    static func decodeDetailResponse(_ data: Data) throws -> SubtitleFile {
        let envelope = try JSONDecoder().decode(DetailEnvelope.self, from: data)
        try checkStatus(envelope.status)
        guard let file = envelope.sub?.subs?.first?.filelist?
            .first(where: { supportedSubtitleExtensions.contains(URL(fileURLWithPath: $0.fileName).pathExtension.lowercased()) }) else {
            throw AssrtSubtitleError.noDirectSubtitleFile
        }
        return file
    }

    static func validatedSubtitleURL(_ value: String) throws -> URL {
        guard let url = URL(string: value),
              url.user == nil, url.password == nil,
              AssrtHostPolicy.allows(url) else {
            throw AssrtSubtitleError.unsafeDownloadLink
        }
        return url
    }

    private static func checkStatus(_ status: Int) throws {
        switch status {
        case 0: return
        case 101: throw AssrtSubtitleError.queryTooShort
        case 20001: throw AssrtSubtitleError.invalidToken
        case 30900: throw AssrtSubtitleError.rateLimited
        default: throw AssrtSubtitleError.serviceStatus(status)
        }
    }

    private static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.9"
        return "Denbox v\(version)"
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AssrtSubtitleError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw AssrtSubtitleError.invalidToken }
        if http.statusCode == 429 { throw AssrtSubtitleError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw AssrtSubtitleError.serverStatus(http.statusCode) }
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

    private static func uniqueURL(in directory: URL, baseName: String, extension fileExtension: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")
            suffix += 1
        }
        return candidate
    }

    private struct SearchEnvelope: Decodable {
        let status: Int
        let sub: Payload?

        struct Payload: Decodable {
            let subs: [AssrtSubtitle]?
        }
    }

    private struct DetailEnvelope: Decodable {
        let status: Int
        let sub: Payload?

        struct Payload: Decodable {
            let subs: [SubtitleDetail]?
        }
    }

    private struct SubtitleDetail: Decodable {
        let filelist: [SubtitleFile]?
    }

    struct SubtitleFile: Decodable {
        let url: String
        let fileName: String

        enum CodingKeys: String, CodingKey {
            case url
            case fileName = "f"
        }
    }
}

private enum AssrtHostPolicy {
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased(),
              ["assrt.net", "makedie.me"].contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else {
            return false
        }
        guard let port = url.port else { return true }
        return (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
    }
}

private final class AssrtRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, AssrtHostPolicy.allows(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
