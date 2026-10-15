import Foundation

struct DownloadRequestSource: Sendable {
    let url: URL
    let headers: [String: String]
}

struct DownloadReport: Sendable {
    let byteCount: Int64
    let segmentCount: Int
    let contentType: String?
}

enum SegmentedDownloadError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case invalidRangeResponse
    case destinationExists
    case unsupportedAdaptiveStream

    var errorDescription: String? {
        switch self {
        case .invalidURL: "This source is not a direct HTTP or HTTPS file link."
        case .invalidResponse: "The server returned an invalid download response."
        case .httpStatus(let status): "The server rejected the download (HTTP \(status))."
        case .invalidRangeResponse: "The server returned an invalid byte-range response."
        case .destinationExists: "A file with this name already exists."
        case .unsupportedAdaptiveStream: "This source is an adaptive HLS/DASH playlist. Choose a direct MP4 or MKV source to download."
        }
    }
}

enum SegmentedDownloader {
    private static let minimumParallelSize: Int64 = 8 * 1024 * 1024
    private static let targetSegmentSize: Int64 = 4 * 1024 * 1024
    private static let maximumSegments = 8

    static func download(
        source: DownloadRequestSource,
        to destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64?, Int, Int?) -> Void = { _, _, _, _ in }
    ) async throws -> DownloadReport {
        guard let scheme = source.url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              source.url.host != nil else { throw SegmentedDownloadError.invalidURL }
        try prepareDestination(destination)

        var probe = makeRequest(source)
        probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (probeFile, probeResponse) = try await URLSession.shared.download(for: probe)
        guard let http = probeResponse as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: probeFile)
            throw SegmentedDownloadError.invalidResponse
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")

        if http.statusCode == 200 {
            let size = fileSize(probeFile)
            try FileManager.default.moveItem(at: probeFile, to: destination)
            onProgress(size, size, 1, 1)
            return DownloadReport(byteCount: size, segmentCount: 1, contentType: contentType)
        }
        guard http.statusCode == 206 else {
            try? FileManager.default.removeItem(at: probeFile)
            throw SegmentedDownloadError.httpStatus(http.statusCode)
        }

        guard let range = contentRange(http.value(forHTTPHeaderField: "Content-Range")),
              range.start == 0, range.end == 0, range.total > 0 else {
            try? FileManager.default.removeItem(at: probeFile)
            return try await downloadWholeFile(source: source, to: destination, knownTotal: nil, onProgress: onProgress)
        }
        try? FileManager.default.removeItem(at: probeFile)

        guard range.total >= minimumParallelSize else {
            return try await downloadWholeFile(source: source, to: destination, knownTotal: range.total, onProgress: onProgress)
        }

        let segmentCount = min(maximumSegments, max(2, Int((range.total + targetSegmentSize - 1) / targetSegmentSize)))
        onProgress(0, range.total, 0, segmentCount)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("Denbox-Download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let segments = makeRanges(total: range.total, count: segmentCount)
        let progress = SegmentedProgress(totalBytes: range.total, segmentCount: segmentCount, onProgress: onProgress)
        var completedFiles = Array<URL?>(repeating: nil, count: segmentCount)

        do {
            try await withThrowingTaskGroup(of: (Int, URL, Int64).self) { group in
                for (index, byteRange) in segments.enumerated() {
                    let partURL = workspace.appendingPathComponent(String(format: "part-%03d", index))
                    group.addTask {
                        let bytes = try await downloadRange(
                            source: source,
                            range: byteRange,
                            total: range.total,
                            to: partURL,
                            onBytes: { progress.received($0, total: range.total) }
                        )
                        return (index, partURL, bytes)
                    }
                }
                for try await (index, fileURL, _) in group {
                    completedFiles[index] = fileURL
                    progress.completedSegment()
                }
            }
        } catch {
            guard shouldRetryAsSingleDownload(error) else { throw error }
            onProgress(0, range.total, 0, 1)
            return try await downloadWholeFile(source: source, to: destination, knownTotal: range.total, onProgress: onProgress)
        }

        do {
            try concatenate(completedFiles.compactMap { $0 }, to: destination)
            let actualSize = fileSize(destination)
            guard actualSize == range.total else {
                try? FileManager.default.removeItem(at: destination)
                throw SegmentedDownloadError.invalidRangeResponse
            }
            return DownloadReport(byteCount: actualSize, segmentCount: segmentCount, contentType: contentType)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func downloadRange(
        source: DownloadRequestSource,
        range: ClosedRange<Int64>,
        total: Int64,
        to partURL: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> Int64 {
        var request = makeRequest(source)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let http: HTTPURLResponse
        do {
            http = try await downloadToFile(request, destination: partURL, expectedBytes: range.upperBound - range.lowerBound + 1) { bytes, _ in
                onBytes(bytes)
            }
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            throw error
        }
        guard http.statusCode == 206,
              let actual = contentRange(http.value(forHTTPHeaderField: "Content-Range")),
              actual.start == range.lowerBound,
              actual.end == range.upperBound,
              actual.total == total else {
            try? FileManager.default.removeItem(at: partURL)
            if http.statusCode == 200 || http.statusCode == 206 {
                throw SegmentedDownloadError.invalidRangeResponse
            }
            throw SegmentedDownloadError.httpStatus(http.statusCode)
        }
        let expectedBytes = range.upperBound - range.lowerBound + 1
        guard fileSize(partURL) == expectedBytes else {
            try? FileManager.default.removeItem(at: partURL)
            throw SegmentedDownloadError.invalidRangeResponse
        }
        return expectedBytes
    }

    private static func downloadWholeFile(
        source: DownloadRequestSource,
        to destination: URL,
        knownTotal: Int64?,
        onProgress: @escaping @Sendable (Int64, Int64?, Int, Int?) -> Void
    ) async throws -> DownloadReport {
        onProgress(0, knownTotal, 0, 1)
        let http: HTTPURLResponse
        do {
            http = try await downloadToFile(makeRequest(source), destination: destination, expectedBytes: nil) { completed, expected in
                onProgress(completed, expected, 0, 1)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        guard (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: destination)
            throw SegmentedDownloadError.httpStatus(http.statusCode)
        }
        let size = fileSize(destination)
        onProgress(size, size, 1, 1)
        return DownloadReport(
            byteCount: size,
            segmentCount: 1,
            contentType: http.value(forHTTPHeaderField: "Content-Type")
        )
    }

    private static func downloadToFile(
        _ request: URLRequest,
        destination: URL,
        expectedBytes: Int64?,
        onBytes: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> HTTPURLResponse {
        let delegate = SegmentDownloadDelegate(destination: destination, expectedBytes: expectedBytes, onBytes: onBytes)
        return try await delegate.download(request)
    }

    private static func shouldRetryAsSingleDownload(_ error: Error) -> Bool {
        if case SegmentedDownloadError.invalidRangeResponse = error { return true }
        if case SegmentedDownloadError.httpStatus = error { return true }
        return false
    }

    private static func makeRequest(_ source: DownloadRequestSource) -> URLRequest {
        var request = URLRequest(url: source.url)
        request.timeoutInterval = 60
        for (name, value) in source.headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private static func prepareDestination(_ destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw SegmentedDownloadError.destinationExists
        }
    }

    private static func makeRanges(total: Int64, count: Int) -> [ClosedRange<Int64>] {
        let baseSize = total / Int64(count)
        var start: Int64 = 0
        return (0..<count).map { index in
            let size = index == count - 1 ? total - start : baseSize
            let range = start...(start + size - 1)
            start += size
            return range
        }
    }

    private static func contentRange(_ value: String?) -> (start: Int64, end: Int64, total: Int64)? {
        guard let value else { return nil }
        let pieces = value.split(separator: " ")
        guard pieces.count == 2, pieces[0].lowercased() == "bytes" else { return nil }
        let rangeAndTotal = pieces[1].split(separator: "/")
        guard rangeAndTotal.count == 2, let total = Int64(rangeAndTotal[1]), total > 0 else { return nil }
        let endpoints = rangeAndTotal[0].split(separator: "-")
        guard endpoints.count == 2, let start = Int64(endpoints[0]), let end = Int64(endpoints[1]) else { return nil }
        return (start, end, total)
    }

    private static func concatenate(_ parts: [URL], to destination: URL) throws {
        guard !parts.isEmpty else { throw SegmentedDownloadError.invalidRangeResponse }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw SegmentedDownloadError.invalidResponse
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for part in parts {
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
                try output.write(contentsOf: data)
            }
        }
        try output.synchronize()
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private final class SegmentedProgress: @unchecked Sendable {
    private let lock = NSLock()
    private let totalBytes: Int64
    private let segmentCount: Int
    private let onProgress: @Sendable (Int64, Int64?, Int, Int?) -> Void
    private var downloadedBytes: Int64 = 0
    private var completedSegments = 0

    init(totalBytes: Int64, segmentCount: Int,
         onProgress: @escaping @Sendable (Int64, Int64?, Int, Int?) -> Void) {
        self.totalBytes = totalBytes
        self.segmentCount = segmentCount
        self.onProgress = onProgress
    }

    func received(_ bytes: Int64, total: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        downloadedBytes = min(totalBytes, downloadedBytes + bytes)
        let current = downloadedBytes
        let completed = completedSegments
        lock.unlock()
        onProgress(current, total, completed, segmentCount)
    }

    func completedSegment() {
        lock.lock()
        completedSegments = min(segmentCount, completedSegments + 1)
        let bytes = downloadedBytes
        let completed = completedSegments
        lock.unlock()
        onProgress(bytes, totalBytes, completed, segmentCount)
    }
}

private final class SegmentDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedBytes: Int64?
    private let onBytes: @Sendable (Int64, Int64?) -> Void
    private let stateLock = NSLock()
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var lastReportedBytes: Int64 = 0
    private var protocolFailure: Error?
    private var fileFailure: Error?
    private var didMoveFile = false

    init(destination: URL, expectedBytes: Int64?, onBytes: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.destination = destination
        self.expectedBytes = expectedBytes
        self.onBytes = onBytes
    }

    func download(_ request: URLRequest) async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: request)
                stateLock.lock()
                self.continuation = continuation
                self.session = session
                self.task = task
                stateLock.unlock()
                task.resume()
                if Task.isCancelled { task.cancel() }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if let expectedBytes, totalBytesWritten > expectedBytes {
            if protocolFailure == nil { protocolFailure = SegmentedDownloadError.invalidRangeResponse }
            downloadTask.cancel()
            return
        }
        let delta = totalBytesWritten - lastReportedBytes
        lastReportedBytes = totalBytesWritten
        let reportedTotal: Int64? = expectedBytes ?? (totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        onBytes(delta, reportedTotal)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            didMoveFile = true
        } catch {
            fileFailure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<HTTPURLResponse, Error>
        if let protocolFailure {
            result = .failure(protocolFailure)
        } else if let error {
            result = .failure(error)
        } else if let fileFailure {
            result = .failure(fileFailure)
        } else if !didMoveFile {
            result = .failure(SegmentedDownloadError.invalidResponse)
        } else if let response = task.response as? HTTPURLResponse {
            result = .success(response)
        } else {
            result = .failure(SegmentedDownloadError.invalidResponse)
        }
        finish(result)
    }

    private func cancel() {
        stateLock.lock()
        let task = self.task
        stateLock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        stateLock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        stateLock.unlock()
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }
}
