# Denbox for Mac

Denbox is a native SwiftUI movie and series library for macOS. It keeps the catalog and My List in SQLite, uses the API route patterns found in the supplied Simba APK for search and title details, and presents film and series pages with metadata, seasons, episodes, and selectable playback sources.

The embedded player is built with AVKit. It supports seeking, playback speed, full screen, Picture in Picture, audio/subtitle selection, local SRT/VTT files (UTF-8 and Windows-1256), subtitle delay and styling, and an IINA fallback for sources AVKit cannot open. It does not yet provide full IINA/libmpv feature parity; AVFoundation still cannot play every codec or stream type.

## API and data

- The Mac client uses the APK route shapes `first/{key}`, `search/{query}/{key}`, `movie/by/{id}/{key}`, and `season/by/serie/{id}/{key}`. It uses the current HTTPS origin advertised by the APK config endpoint (`ninwinios.info/api`), then falls back to the known HTTPS service host. Catalog feeds remain on their configured HTTPS endpoints. The current cache remains available in `~/Library/Application Support/Simba/library.sqlite` so upgrading the app name does not discard the existing catalog.
- Opened movie and series detail responses are stored in that same SQLite database. Reopening a title displays its saved details immediately, including when the Mac is offline; entries older than 24 hours refresh in the background and update the page when fresh API data arrives.
- Denbox does not call Frappe routes. API keys stay in macOS Keychain under the existing Simba service identity; they are not stored in this repository or app bundle.
- The media API can return plain HTTP streams and redirect them across hosts. For this personal build, ATS allows arbitrary media and network loads so AVKit can follow those HTTP redirects. API routes in Denbox still use HTTPS. This broad setting lowers transport security for network connections made by the app.
- Movie and series feeds are paginated in batches of 30. Use **Load more titles** in the Movies or TV Shows sections to continue through the feed. Pages are cached in the existing SQLite library, so titles loaded earlier remain available after restarting Denbox.
- Selecting a title opens a full detail page in the main window, with navigation back to the catalog. Direct video links from movie details and individual episode details can be downloaded to `~/Downloads/Denbox`. When the source honors HTTP byte ranges, Denbox downloads up to eight parts concurrently, reports bytes as they arrive, and verifies the assembled size; sources that reject or ignore ranges fall back to a normal download. HLS (`.m3u8`) and DASH (`.mpd`) playlists are not converted by this downloader.
- **Download / refresh IMDb data** in Settings fetches IMDb's official public datasets over HTTPS. The current source files are about 290 MB compressed; the local SQLite index is about 2.7 GB. Denbox imports series and episode titles, release years, genres, ratings, votes, and episode-to-season numbering into `~/Library/Application Support/Denbox/imdb-metadata.sqlite`. The compressed source files are temporary and deleted after import. Series matching prioritizes exact titles and uses release year to rank duplicate or fuzzy matches, so an inaccurate year does not block an exact older-series match; episode matching uses episode title and then reorders/relabels using IMDb season and episode numbers. Similar titles are a local genre-overlap ranking, not IMDb's official recommendations. Clicking a similar series searches the Simba catalog and opens the matching series details and episodes. Descriptions still come from the configured media API because IMDb's downloadable datasets do not include plot text. The IMDb dataset is for personal, non-commercial use; it is not bundled with releases. Attribution: “Information courtesy of IMDb (https://www.imdb.com). Used with permission.”

## Build

```sh
mkdir -p dist/Denbox.app/Contents/{MacOS,Resources}
cp Resources/Info.plist dist/Denbox.app/Contents/Info.plist
cp Resources/AppIcon.icns dist/Denbox.app/Contents/Resources/AppIcon.icns
cp Resources/Denbox-Icon.png dist/Denbox.app/Contents/Resources/Denbox-Icon.png
swiftc -parse-as-library -swift-version 5 -O \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework AVKit \
  -framework Security -framework UniformTypeIdentifiers -lsqlite3 \
  Sources/SimbaMac.swift Sources/SegmentedDownloader.swift Sources/IMDbMetadata.swift \
  -o dist/Denbox.app/Contents/MacOS/Denbox
codesign --force --deep --sign - dist/Denbox.app
```

The bundle identifier and existing Keychain/database locations intentionally retain the Simba identity so this rename keeps the current API credentials, catalog cache, and My List. This build targets Apple Silicon and macOS 13 or newer. It is ad-hoc signed and not notarized.

## Verification

`Tests/DenboxSourceParserTests.swift` checks movie and series source parsing, including the API's `downloadas` flag. `Tests/SegmentedDownloaderTests.swift` uses a local synthetic HTTP server to verify concurrent range assembly/checksum and the no-range fallback. `Tests/DenboxLiveAPITests.swift` uses the existing Keychain keys and live API, updates the local catalog cache, checks movie and episode links, verifies arbitrary byte ranges on a real media source, then confirms that movie pagination adds another page. It intentionally prints counts only, never keys or media URLs.
