import SwiftUI

struct OnlineSubtitleSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let videoURL: URL
    let apiKey: String
    let onLoadSubtitle: (URL) -> Void

    @State private var query: String
    @State private var language = "fa"
    @State private var results: [OnlineSubtitleResult] = []
    @State private var isSearching = false
    @State private var downloadingID: String?
    @State private var message: String?

    init(videoURL: URL, initialQuery: String, apiKey: String, onLoadSubtitle: @escaping (URL) -> Void) {
        self.videoURL = videoURL
        self.apiKey = apiKey
        self.onLoadSubtitle = onLoadSubtitle
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find subtitles online")
                        .font(.denbox(size: 20, weight: .bold))
                    Text("Search OpenSubtitles and load the selected subtitle in Denbox.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("OpenSubtitles API key required", systemImage: "key.horizontal")
                        .font(.denbox(size: 13, weight: .semibold))
                    Text("Add your own API key in Denbox Settings. It is stored in macOS Keychain and is sent only to OpenSubtitles.")
                        .font(.denbox(size: 11))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Get an OpenSubtitles API key", destination: URL(string: "https://www.opensubtitles.com/en/consumers")!)
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
                    Button(action: search) {
                        Label(isSearching ? "Searching…" : "Search", systemImage: isSearching ? "hourglass" : "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }

                if let message {
                    Text(DenboxLanguage.localizedMessage(message))
                        .font(.denbox(size: 11))
                        .foregroundStyle(message.hasPrefix("OpenSubtitles request failed") ? Color.orange : Color.white.opacity(0.65))
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

    private func resultRow(_ result: OnlineSubtitleResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.attributes.language?.uppercased() ?? "??")
                        .font(.denbox(size: 10, weight: .bold).monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1), in: Capsule())
                    if result.attributes.movieHashMatch == true {
                        Label("Exact file match", systemImage: "checkmark.seal.fill")
                            .font(.denbox(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
                Text(result.attributes.release?.isEmpty == false ? result.attributes.release! : "Subtitle \(result.id)")
                    .font(.denbox(size: 12, weight: .medium))
                    .lineLimit(2)
                Text(DenboxLanguage.localizedMessage("Downloads: \(result.attributes.downloadCount ?? 0) · Files: \(result.attributes.files.count)"))
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
            .disabled(downloadingID != nil || result.attributes.files.isEmpty)
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
                results = try await OpenSubtitlesClient(apiKey: apiKey).search(
                    query: query,
                    videoURL: videoURL,
                    language: language
                )
                if results.isEmpty { message = "No subtitles matched this title and language." }
            } catch {
                message = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func download(_ result: OnlineSubtitleResult) {
        guard downloadingID == nil else { return }
        downloadingID = result.id
        message = nil
        Task {
            do {
                let url = try await OpenSubtitlesClient(apiKey: apiKey).download(result, forTitle: query)
                onLoadSubtitle(url)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            downloadingID = nil
        }
    }
}
