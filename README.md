# Denbox for Mac

Denbox is a native SwiftUI movie and series library for macOS. It keeps the catalog and My List in SQLite, uses the API route patterns found in the supplied Simba APK for search and title details, and presents film and series pages with metadata, seasons, episodes, and selectable playback sources.

The embedded player is built with AVKit. It supports seeking, playback speed, full screen, Picture in Picture, audio/subtitle selection, local SRT/VTT files (UTF-8 and Windows-1256), subtitle delay and styling. MKV, AVI, WMV, FLV, WebM, and DASH media are handed to IINA, and failed embedded playback refreshes its API link once before falling back to IINA. AVFoundation still cannot play every codec or stream type.

## API and data

- The Mac client uses the APK route shapes `first/{key}`, `search/{query}/{key}`, `movie/by/{id}/{key}`, and `season/by/serie/{id}/{key}`. It uses the current HTTPS origin advertised by the APK config endpoint (`ninwinios.info/api`), then falls back to the known HTTPS service host. Catalog feeds remain on their configured HTTPS endpoints. The current cache remains available in `~/Library/Application Support/Simba/library.sqlite` so upgrading the app name does not discard the existing catalog.
- Opened movie and series detail responses are stored in that same SQLite database. Reopening a title displays its saved details immediately, including when the Mac is offline; entries older than five minutes refresh in the background and update the page when fresh API data arrives.
- Denbox does not call Frappe routes. API keys stay in macOS Keychain under the existing Simba service identity; they are not stored in this repository or app bundle.
- The media API can return plain HTTP streams and redirect them across hosts. For this personal build, ATS allows arbitrary media and network loads so AVKit can follow those HTTP redirects. API routes in Denbox still use HTTPS. This broad setting lowers transport security for network connections made by the app.
- Movie and series feeds are paginated in batches of 30. Use **Load more titles** in the Movies or TV Shows sections to continue through the feed. Pages are cached in the existing SQLite library, so titles loaded earlier remain available after restarting Denbox.
- Selecting a title opens a full detail page in the main window, with navigation back to the catalog. Direct video links from movie details and individual episode details can be downloaded to `~/Downloads/Denbox`. Completed downloads are linked to their catalog title and episode in SQLite, so reopening a detail page shows an offline badge and a **Play Offline** action; missing files are not shown as available. When the source honors HTTP byte ranges, Denbox downloads up to eight parts concurrently, reports bytes as they arrive, and verifies the assembled size; sources that reject or ignore ranges fall back to a normal download. HLS (`.m3u8`) and DASH (`.mpd`) playlists are not converted by this downloader.
- **Download / refresh IMDb data** in Settings fetches IMDb's official public datasets over HTTPS. Denbox imports title metadata, ratings, episode numbering, person names, principal cast credits, and director/writer credits into `~/Library/Application Support/Denbox/imdb-metadata.sqlite`. The IMDb People page searches the local name index and shows paginated movie and TV filmographies; selecting a credit searches the Simba catalog and opens its details. The compressed source files are temporary and deleted after import. The IMDb Charts page builds local top-rated and most-voted lists from ratings and votes; its Top 250 style ranking is an approximation because the official chart eligibility formula is not in the downloadable dataset. Trending embeds IMDb's live Most Popular Movies and TV Shows charts, and Box Office embeds the live worldwide lifetime-gross chart from Box Office Mojo. IMDb's official bulk files contain no photos, biographies, plot text, or franchise membership. Title posters are matched through the configured Simba catalog and cached in `~/Library/Application Support/Simba/library.sqlite`; IMDb Franchises opens IMDb's live franchise interests and sends clicked title IDs to the local IMDb/Simba title lookup. Series matching prioritizes exact titles and uses release year to rank duplicate or fuzzy matches. Episodes match by title first and fall back to season/episode numbering such as `S01E01`, then display IMDb rating and vote count where available. Similar titles are a local genre-overlap ranking, not IMDb's official recommendations. Descriptions still come from the configured media API. The IMDb dataset is for personal, non-commercial use; it is not bundled with releases. Attribution: “Information courtesy of IMDb (https://www.imdb.com). Used with permission.”

- Completed downloads store their catalog and episode IDs in SQLite. Reopening the title shows an offline indicator and a **Play Offline** action; Denbox checks that the file still exists before offering it.

## Build

```sh
mkdir -p dist/Denbox.app/Contents/{MacOS,Resources}
cp Resources/Info.plist dist/Denbox.app/Contents/Info.plist
cp Resources/AppIcon.icns dist/Denbox.app/Contents/Resources/AppIcon.icns
cp Resources/Denbox-Icon.png dist/Denbox.app/Contents/Resources/Denbox-Icon.png
swiftc -parse-as-library -swift-version 5 -O \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework AVKit \
  -framework Security -framework UniformTypeIdentifiers -framework WebKit -lsqlite3 \
  Sources/SimbaMac.swift Sources/SegmentedDownloader.swift Sources/IMDbMetadata.swift Sources/ViewingActivity.swift \
  -o dist/Denbox.app/Contents/MacOS/Denbox
codesign --force --deep --sign - dist/Denbox.app
```

The bundle identifier and existing Keychain/database locations intentionally retain the Simba identity so this rename keeps the current API credentials, catalog cache, and My List. This build targets Apple Silicon and macOS 13 or newer. It is ad-hoc signed and not notarized.

## Verification

`Tests/DenboxSourceParserTests.swift` checks movie and series source parsing, including the API's `downloadas` flag. `Tests/SegmentedDownloaderTests.swift` uses a local synthetic HTTP server to verify concurrent range assembly/checksum and the no-range fallback. `Tests/DenboxLiveAPITests.swift` uses the existing Keychain keys and live API, updates the local catalog cache, checks movie and episode links, verifies arbitrary byte ranges on a real media source, then confirms that movie pagination adds another page. It intentionally prints counts only, never keys or media URLs.
