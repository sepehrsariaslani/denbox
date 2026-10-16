import SwiftUI

extension Font {
    static func denbox(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let postScriptName: String
        if weight == .black {
            postScriptName = "Peyda-Black"
        } else if weight == .heavy {
            postScriptName = "Peyda-ExtraBold"
        } else if weight == .bold {
            postScriptName = "Peyda-Bold"
        } else if weight == .semibold {
            postScriptName = "Peyda-SemiBold"
        } else if weight == .medium {
            postScriptName = "Peyda-Medium"
        } else if weight == .light {
            postScriptName = "Peyda-Light"
        } else if weight == .thin {
            postScriptName = "Peyda-Thin"
        } else if weight == .ultraLight {
            postScriptName = "Peyda-ExtraLight"
        } else {
            postScriptName = "Peyda-Regular"
        }
        return .custom(postScriptName, size: size)
    }
}

enum DenboxLanguage {
    static let preferenceKey = "denbox.interfaceLanguage"
    static let defaultCode = persianCode
    static let persianCode = "fa"
    static let englishCode = "en"

    static var selectedCode: String {
        UserDefaults.standard.string(forKey: preferenceKey) == englishCode ? englishCode : defaultCode
    }

    static func locale(for code: String) -> Locale {
        Locale(identifier: code == englishCode ? englishCode : persianCode)
    }

    static func layoutDirection(for code: String) -> LayoutDirection {
        code == englishCode ? .leftToRight : .rightToLeft
    }

    static func localizedMediaKind(_ value: String) -> String {
        guard selectedCode != englishCode else { return value }
        return switch value {
        case "Movie": "فیلم"
        case "Series": "سریال"
        default: value
        }
    }

    static func localizedProfession(_ value: String) -> String {
        guard selectedCode != englishCode else { return value.replacingOccurrences(of: "_", with: " ").capitalized }
        let normalized = value.replacingOccurrences(of: "_", with: " ").lowercased()
        let names: [String: String] = [
            "actor": "بازیگر",
            "actress": "بازیگر",
            "director": "کارگردان",
            "writer": "نویسنده",
            "producer": "تهیه‌کننده",
            "composer": "آهنگ‌ساز",
            "cinematographer": "فیلم‌بردار",
            "editor": "تدوین‌گر",
            "production designer": "طراح صحنه",
            "art director": "مدیر هنری",
            "casting director": "مدیر انتخاب بازیگر",
            "assistant director": "دستیار کارگردان",
            "production manager": "مدیر تولید",
            "sound department": "صدابردار",
            "visual effects": "جلوه‌های بصری",
            "self": "خودش",
            "archive footage": "تصاویر آرشیوی"
        ]
        return names[normalized] ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func localizedMessage(_ message: String) -> String {
        guard selectedCode != englishCode,
              let path = Bundle.main.path(forResource: persianCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return message }

        let dynamicKeys: [(pattern: String, key: String)] = [
            (#"^The embedded playback engine could not start: (.+)$"#, "The embedded playback engine could not start: %@"),
            (#"^The embedded video renderer could not initialize: (.+)$"#, "The embedded video renderer could not initialize: %@"),
            (#"^The video source could not be opened: (.+)$"#, "The video source could not be opened: %@"),
            (#"^Playback failed: (.+)$"#, "Playback failed: %@"),
            (#"^Error code (\d+)$"#, "Error code %@"),
            (#"^Updated: (.+) · (\d+) images$"#, "Updated: %@ · %@ images"),
            (#"^Visible episodes \((\d+)\)$"#, "Visible episodes (%@)"),
            (#"^The link must use HTTPS and point to a public title page on (.+)\.$"#, "The link must use HTTPS and point to a public title page on %@."),
            (#"^Public details from (.+)$"#, "Public details from %@"),
            (#"^Visible episodes on this page \((\d+)\)$"#, "Visible episodes on this page (%@)"),
            (#"^The public page failed to load: (.+)$"#, "The public page failed to load: %@"),
            (#"^Could not connect to the public page: (.+)$"#, "Could not connect to the public page: %@"),
            (#"^Could not read the visible page text: (.+)$"#, "Could not read the visible page text: %@"),
            (#"^Filter genre: (.+)$"#, "Filter genre: %@"),
            (#"^Browse titles in (.+)$"#, "Browse titles in %@"),
            (#"^Open (.+) filmography$"#, "Open %@ filmography"),
            (#"^(\d+) titles in IMDb · (.+)$"#, "%@ titles in IMDb · %@"),
            (#"^Watched (.+) of (.+)$"#, "Watched %@ of %@"),
            (#"^Resume at (.+)$"#, "Resume at %@"),
            (#"^Season downloads: (\d+) added · (\d+) unavailable · (\d+) already queued or downloaded$"#, "Season downloads: %@ added · %@ unavailable · %@ already queued or downloaded"),
            (#"^Watch time: (.+)$"#, "Watch time: %@"),
            (#"^(\d+(?:\.\d+)?) hours$"#, "%@ hours"),
            (#"^Could not save the viewing data export: (.+)$"#, "Could not save the viewing data export: %@"),
            (#"^Could not read viewing data: (.+)$"#, "Could not read viewing data: %@"),
            (#"^Progress records: (\d+)$"#, "Progress records: %@"),
            (#"^History sessions: (\d+)$"#, "History sessions: %@"),
            (#"^Personal ratings: (\d+)$"#, "Personal ratings: %@"),
            (#"^(.+)× Speed$"#, "%@× Speed"),
            (#"^Audio (\d+)$"#, "Audio %@"),
            (#"^Video (\d+)$"#, "Video %@"),
            (#"^Subtitle (\d+)$"#, "Subtitle %@"),
            (#"^Chapter (\d+)$"#, "Chapter %@"),
            (#"^Chapters: (\d+)$"#, "Chapters: %@"),
            (#"^Local database · (\d+) movies · (\d+) series$"#, "Local database · %@ movies · %@ series"),
            (#"^Live catalog unavailable\. Showing (\d+) saved movies and (\d+) saved series\.$"#, "Live catalog unavailable. Showing %@ saved movies and %@ saved series."),
            (#"^Live catalog loaded · (\d+) movies · (\d+) series · (movies|series) feed unavailable$"#, "Live catalog loaded · %@ movies · %@ series · %@ feed unavailable"),
            (#"^Live catalog · (\d+) movies · (\d+) series$"#, "Live catalog · %@ movies · %@ series"),
            (#"^Loaded (\d+) more titles · (\d+) movies · (\d+) series$"#, "Loaded %@ more titles · %@ movies · %@ series"),
            (#"^Loaded (\d+) titles; another catalog page failed\. Retry to continue\.$"#, "Loaded %@ titles; another catalog page failed. Retry to continue."),
            (#"^Updated · (\d+) movies · (\d+) series$"#, "Updated · %@ movies · %@ series"),
            (#"^(\d+) results · From (.+)$"#, "%@ results · From %@"),
            (#"^(\d+) titles ready to resume$"#, "%@ titles ready to resume"),
            (#"^(\d+) recent sessions stored on this Mac$"#, "%@ recent sessions stored on this Mac"),
            (#"^Rate (\d+) out of 5 stars$"#, "Rate %@ out of 5 stars"),
            (#"^(\d+) titles · From (.+)$"#, "%@ titles · From %@"),
            (#"^Simba did not return a matching title for (.+)\.$"#, "Simba did not return a matching title for %@."),
            (#"^IMDb dataset download failed: (.+)$"#, "IMDb dataset download failed: %@"),
            (#"^IMDb dataset import failed: (.+)$"#, "IMDb dataset import failed: %@"),
            (#"^IMDb dataset ready · updated (.+)$"#, "IMDb dataset ready · updated %@"),
            (#"^Checking public metadata for (\d+) titles…$"#, "Checking public metadata for %@ titles…"),
            (#"^Checked public references for (\d+) titles\.$"#, "Checked public references for %@ titles."),
            (#"^(.+) votes$"#, "%@ votes"),
            (#"^Downloading IMDb (.+)…$"#, "Downloading IMDb %@…")
        ]

        for entry in dynamicKeys {
            guard var values = captureGroups(in: message, pattern: entry.pattern) else { continue }
            if entry.key == "Downloading IMDb %@…", let name = values.first {
                values[0] = [
                    "titles": "عنوان‌ها",
                    "episodes": "قسمت‌ها",
                    "ratings": "امتیازها",
                    "names": "نام‌ها",
                    "principals": "بازیگران و عوامل اصلی",
                    "crew": "عوامل"
                ][name] ?? name
            }
            let format = bundle.localizedString(forKey: entry.key, value: entry.key, table: nil)
            return String(format: format, locale: locale(for: selectedCode), arguments: values)
        }

        return bundle.localizedString(forKey: message, value: message, table: nil)
    }

    private static func captureGroups(in value: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.location == 0,
              match.range.length == (value as NSString).length else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }
}

extension LibrarySection {
    var displayName: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .forYou: "For You"
        case .genres: "Genres"
        case .continueWatching: "Continue Watching"
        case .watchHistory: "Watch History"
        case .viewingStats: "Viewing Stats"
        case .movies: "Movies"
        case .shows: "TV Shows"
        case .imdbCharts: "IMDb Charts"
        case .imdbPeople: "IMDb People"
        case .imdbFranchises: "IMDb Franchises"
        case .watchlist: "My List"
        case .myRatings: "My Ratings"
        case .downloads: "Downloads"
        }
    }
}
