import SwiftUI

private enum OnlineSubtitleProvider: String, CaseIterable, Identifiable {
    case openSubtitles
    case assrt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openSubtitles: "OpenSubtitles"
        case .assrt: "ASSRT"
        }
    }
}

private enum SubtitleSearchEntry: Identifiable {
    case openSubtitles(OnlineSubtitleResult)
    case assrt(AssrtSubtitle)

    var id: String {
        switch self {
        case .openSubtitles(let result): "opensubtitles-\(result.id)"
        case .assrt(let result): result.stableID
        }
    }

    var title: String {
        switch self {
        case .openSubtitles(let result):
            result.attributes.release?.isEmpty == false ? result.attributes.release! : "Subtitle \(result.id)"
        case .assrt(let result):
            result.nativeName?.isEmpty == false ? result.nativeName! : (result.videoName?.isEmpty == false ? result.videoName! : "Subtitle \(result.id)")
        }
    }

    var languageLabel: String {
        switch self {
        case .openSubtitles(let result): result.attributes.language?.uppercased() ?? "??"
        case .assrt(let result): result.language?.description ?? "ASSRT"
        }
    }

    var isExactMatch: Bool {
        if case .openSubtitles(let result) = self { return result.attributes.movieHashMatch == true }
        return false
    }

    var detailText: String {
        switch self {
        case .openSubtitles(let result):
            "Downloads: \(result.attributes.downloadCount ?? 0) · Files: \(result.attributes.files.count)"
        case .assrt(let result):
            [result.subtype, result.releaseSite, result.uploadTime].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }
}

struct OnlineSubtitleSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let videoURL: URL
    let apiKey: String
    let assrtToken: String
    let onLoadSubtitle: (URL) -> Void

    @State private var provider: OnlineSubtitleProvider = .openSubtitles
    @State private var query: String
    @State private var language = "fa"
    @State private var results: [SubtitleSearchEntry] = []
    @State private var isSearching = false
    @State private var downloadingID: String?
    @State private var message: String?

    init(videoURL: URL, initialQuery: String, apiKey: String, assrtToken: String, onLoadSubtitle: @escaping (URL) -> Void) {
        self.videoURL = videoURL
        self.apiKey = apiKey
        self.assrtToken = assrtToken
        self.onLoadSubtitle = onLoadSubtitle
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find subtitles online")
                        .font(.denbox(size: 20, weight: .bold))
                    Text("Search OpenSubtitles or ASSRT and load the selected subtitle in Denbox.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                Text("Subtitle provider")
                    .font(.denbox(size: 11, weight: .medium))
                Picker("Subtitle provider", selection: $provider) {
                    ForEach(OnlineSubtitleProvider.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .frame(width: 190)
                .disabled(isSearching || downloadingID != nil)
                Spacer()
                if provider == .assrt {
                    HStack(spacing: 4) {
                        Text("Subtitle service by ASSRT")
                            .font(.denbox(size: 10))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Link("assrt.net", destination: URL(string: "https://assrt.net")!)
                            .font(.denbox(size: 10))
                    }
                }
            }
            .onChange(of: provider) { _ in
                results = []
                message = nil
            }

            if credentialForSelectedProvider.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(provider == .openSubtitles ? "OpenSubtitles API key required" : "ASSRT API token required", systemImage: "key.horizontal")
                        .font(.denbox(size: 13, weight: .semibold))
                    Text(provider == .openSubtitles
                         ? "Add your own API key in Denbox Settings. It is stored in macOS Keychain and is sent only to OpenSubtitles."
                         : "Add your own ASSRT API token in Denbox Settings. It is stored in macOS Keychain and sent only to ASSRT over HTTPS.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    Link(provider == .openSubtitles ? "Get an OpenSubtitles API key" : "ASSRT API documentation and token details",
                         destination: provider == .openSubtitles
                            ? URL(string: "https://www.opensubtitles.com/en/consumers")!
                            : URL(string: "https://assrt.net/api/doc")!)
                        .font(.denbox(size: 11, weight: .medium))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 10) {
                    TextField("Title or release name", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSearching || downloadingID != nil)
                        .onSubmit { search() }
                    Picker("Language", selection: $language) {
                        Text("Persian").tag("fa")
                        Text("English").tag("en")
                        Text("Arabic").tag("ar")
                        Text("Turkish").tag("tr")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Russian").tag("ru")
                        Text("Japanese").tag("ja")
                    }
                    .frame(width: 135)
                    .disabled(provider == .assrt)
                    Button(action: search) {
                        Label(isSearching ? "Searching…" : "Search", systemImage: isSearching ? "hourglass" : "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching || downloadingID != nil || query.trimmingCharacters(in: .whitespacesAndNewlines).count < minimumQueryLength)
                }

                if provider == .assrt {
                    Text("ASSRT returns the language label from each subtitle result; its search API has no language filter.")
                        .font(.denbox(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                if let message {
                    Text(DenboxLanguage.localizedMessage(message))
                        .font(.denbox(size: 11))
                        .foregroundStyle(message.contains("request failed") ? Color.orange : Color.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isSearching {
                    ProgressView("Searching subtitles…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "captions.bubble")
                            .font(.denbox(size: 28))
                            .foregroundStyle(Color.white.opacity(0.65))
                        Text("No subtitle results")
                            .font(.denbox(size: 13, weight: .semibold))
                        Text("Search for a title to see available subtitle files.")
                            .font(.denbox(size: 11))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { result in
                        resultRow(result)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .padding(18)
        .frame(width: 680, height: 520)
        .preferredColorScheme(.dark)
    }

    private var credentialForSelectedProvider: String {
        (provider == .openSubtitles ? apiKey : assrtToken).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var minimumQueryLength: Int { provider == .openSubtitles ? 2 : 4 }

    private func resultRow(_ result: SubtitleSearchEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.languageLabel)
                        .font(.denbox(size: 10, weight: .bold).monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1), in: Capsule())
                    if result.isExactMatch {
                        Label("Exact file match", systemImage: "checkmark.seal.fill")
                            .font(.denbox(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
                Text(result.title)
                    .font(.denbox(size: 12, weight: .medium))
                    .lineLimit(2)
                Text(DenboxLanguage.localizedMessage(result.detailText))
                    .font(.denbox(size: 10))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Spacer(minLength: 4)
            Button {
                download(result)
            } label: {
                Label(downloadingID == result.id ? "Downloading…" : "Download and load", systemImage: downloadingID == result.id ? "hourglass" : "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .disabled(downloadingID != nil)
        }
        .padding(.vertical, 4)
    }

    private func search() {
        guard !isSearching else { return }
        isSearching = true
        message = nil
        results = []
        Task {
            do {
                switch provider {
                case .openSubtitles:
                    results = try await OpenSubtitlesClient(apiKey: apiKey).search(
                        query: query,
                        videoURL: videoURL,
                        language: language
                    ).map { .openSubtitles($0) }
                case .assrt:
                    results = try await AssrtSubtitleClient(token: assrtToken).search(
                        query: query,
                        videoURL: videoURL
                    ).map { .assrt($0) }
                }
                if results.isEmpty { message = "No subtitles matched this search." }
            } catch {
                message = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func download(_ entry: SubtitleSearchEntry) {
        guard downloadingID == nil else { return }
        downloadingID = entry.id
        message = nil
        Task {
            do {
                let url: URL
                switch entry {
                case .openSubtitles(let result):
                    url = try await OpenSubtitlesClient(apiKey: apiKey).download(result, forTitle: query)
                case .assrt(let result):
                    url = try await AssrtSubtitleClient(token: assrtToken).download(result, forTitle: query)
                }
                onLoadSubtitle(url)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            downloadingID = nil
        }
    }
}
