# Denbox shared project context

Updated: 2026-10-16

## Goal and audience

Make Denbox Sepehr's best personal movie and TV app. The current product is a native macOS app, so work should stay Mac-first unless Sepehr changes that direction. Optimize for the daily loop: find something worth watching, start or resume it reliably, and remember what was watched. Keep viewing data local by default; avoid adding accounts, social features, or cloud collection without a clear personal-use need.

Confirmed preference: Persian is the default interface language for personal use. Preserve original/international film, series, person, and provider names. English remains available as an interface option. Persian localization is underway and must be described as partial until all user-facing screens and dynamic status messages are covered.

## Product baseline

See `README.md` for the source of truth on the current build and data boundaries. Existing capabilities include a SQLite catalog and My List, a direct media API, title and episode details, an embedded libmpv player, subtitle controls, offline downloads, and optional local IMDb data for charts, people, ratings, and episode matching.

Competitor references suggest useful patterns rather than a mandate to copy them: Letterboxd combines a film diary, watchlist, ratings, lists, and personal stats; JustWatch emphasizes title availability across services and tracking; Trakt defines playback scrobbling, watch history, watchlists, and favorites; Plex combines universal search and watchlists across providers. Sources: [Letterboxd FAQ](https://letterboxd.com/about/faq/), [JustWatch About](https://www.justwatch.com/us/about), [Trakt API guide](https://developer.trakt.tv/), [Plex Discover](https://www.plex.tv/discover/).

## Current product state

The installed app remains version 0.2.6 (build 8) at `/Users/sepehr/Library/Application Support/MacDupl/c/42505fb2/Home/Applications/Denbox.app`. The current candidate was built from a hash-verified snapshot at `/tmp/denbox-final-push-20261016-r2` as an Apple Silicon macOS 13 app, signed ad hoc, and passed deep signature verification; it has not been installed or launched. Its build reported 32 deprecation warnings from OpenGL and older SwiftUI APIs. Fourteen local tests passed, including IMDb person/genre navigation and the player audio/picture controls. The live catalog API test did not produce a response within 60 seconds. The in-process UI/native computer-use surface was unavailable for a manual walkthrough, so player interaction, resume after relaunch, RTL layout, and live playback still need direct UI verification.

- `LibrarySection` has `For You`, `Genres`, `Continue Watching`, `Watch History`, `Viewing Stats`, and `My Ratings`; `MainWindow` routes to these pages.
- `MediaDatabase` has local watch-progress, watch-session, and genre-preference tables and read/write methods.
- Personal movie and series ratings use a separate local one-to-five-star table. Each rating keeps a title snapshot, appears on poster cards and in the My Ratings sidebar page, and can be changed or cleared independently of IMDb's score. For You uses star-rating affinity for genres and excludes titles already rated; a later IMDb import updates a saved rating's title snapshot so its IMDb identity and genres remain available. Persian and English labels are included. The hash-checked Apple Silicon/macOS 13 snapshot compiled and passed deep ad-hoc signature verification on 2026-10-16; database persistence and recommendation behavior still need runtime verification.
- **For You** now uses private star ratings as a taste signal alongside local watch history and chosen genres, and leaves already-rated titles out of the recommendation list. When IMDb enrichment later supplies a missing IMDb ID or genres, the saved rated-title snapshot is refreshed without changing its rating date. Searching My Ratings stays local and does not call the media API.
- The shared search field matches loaded titles, subtitles, and alternate names. It shows a loading state instead of an immediate no-results message while remote catalog search runs, and searches started from discovery pages display the returned catalog matches. My Ratings search remains local. The changed search UI compiles but has not been manually verified.
- Viewing Stats' JSON backup includes personal ratings and their catalog snapshots with watch progress and session history. Import supports schema versions 1 and 2, previews record counts, and merges transactionally: newer local progress/ratings remain, duplicate history sessions are skipped, and nothing is deleted. Inputs are capped at 50 MB and 100,000 total records. This flow compiles but has not had runtime verification.
- `Tests/PersonalRatingPersistenceTests.swift` is present in the shared worktree for save, reload, update, range-check, and clear behavior. The latest app compile did not execute that test.
- `LibraryModel` now starts, updates, and finishes playback sessions; `LocalPlayerSheet` uses the embedded libmpv controller to save progress and resume from saved positions.
- IMDb-backed metadata and recommendation models now feed discovery and genre-filter views.
- Reference metadata is requested when a title detail page opens, or by the explicit **Check public references for loaded titles** Settings action. It no longer scans the entire catalog automatically at startup, refresh, or pagination. Wikidata and TVmaze fill missing detail fields, with source citations and a local SQLite cache. Wikidata attempts strict title/type matching for series even when there is no IMDb ID. Lookups send title terms or a matched IMDb ID; they do not include viewing history or My List. Filimo/HexDL still require a public title URL and review/save step. The current live provider request path remains unverified in this environment because shell TLS probes could not validate the network certificate. See `README.md` for source and cache details.
- Public title-page import from Filimo and HexDL is available on title details, with a review/edit step before saving locally; Filimo has precedence. Only allowlisted public title pages and visible page content are used. The new source files and Persian localization resource are included in the README build instructions.
- The app now has a saved interface-language preference defaulting to Persian, a Persian/English choice in Settings, right-to-left layout for Persian, and expanded translations for navigation, empty states, download states, dynamic catalog/API messages, IMDb import/charts, genre names, people roles, curated franchise descriptions, Settings, public-title import controls/review sheet/status, viewing-data import preview/status, offline actions, and the embedded player's controls, track labels, and common errors. A static audit of literal SwiftUI labels across the main app, player, and public-page import found no missing Persian keys beyond the brand, system-symbol identifiers, and language names. Dynamic provider/OS/mpv error text still falls back to English, and visual RTL/language switching has not been manually checked.
- Genre and recommendation empty states distinguish a missing IMDb dataset from a ready dataset with no results; genre import now shows an in-progress state.
- `MPVPlaybackController` is connected to the in-app player and reports progress directly to the watch-session model. It exposes video, audio, and subtitle tracks; external audio/subtitle files; chapter selection; A–B loops; audio delay; crop controls; picture and sound adjustments; a five-band equalizer; deinterlacing; and hardware decoding. Cast names can open local IMDb person profiles with paginated filmography credits. Watched-time accounting treats mpv as actively playing only when it is not paused, idle, waiting for cache, seeking, or core-idle. The 14 local tests passed; the latest controls have not had a manual UI walkthrough. The README build command copies libmpv and its runtime libraries from `/Applications/IINA.app/Contents/Frameworks`; this requires IINA installed at that path.
- The unused IINA-monitor path falls back to the last saved progress and duration if it finishes without a positive position snapshot; the current embedded player writes progress directly.
- Episode progress lookup tries the current API ID, then a stable season/episode label, then a unique title when the saved row has no label. When it finds an older row after an API ID change, playback keeps that stored ID to avoid duplicate progress rows.
- Offline title/episode lookup tolerates regenerated episode IDs by matching saved titles when needed.
- `IINAPlaybackMonitor` and its socket fixture remain in the worktree but are not used by the new in-app playback flow. The player uses direct libmpv events/properties instead. Keep the monitor's IPC security notes scoped to that unused path ([mpv IPC documentation](https://github.com/mpv-player/mpv/blob/master/DOCS/man/ipc.rst)).
- `Sources/MPVPlayback.swift` imports the `Sources/MPV` module map and IINA's libmpv runtime. The README now copies every `.dylib` from the installed IINA frameworks and links `libmpv.1.dylib`; review architecture compatibility, runtime install names, signing, and redistribution/licensing before any release.
- Reference-metadata lookups send a matched IMDb ID to Wikidata or a series title to TVmaze. They do not send viewing history or My List, and their result cache is local. Keep that boundary clear if adding providers.
- The libmpv package built and passed deep ad-hoc signature verification on this Apple Silicon Mac. The player currently renders through deprecated AppKit OpenGL APIs; investigate a supported libmpv rendering path for long-term macOS compatibility.

### Acceptance criteria for this workstream

- Every new sidebar section has a useful populated, loading, empty, and missing-IMDb-data state.
- Personal ratings can be added, edited, cleared, and reopened from SQLite; My Ratings retains the title card across catalog refreshes.
- For You reflects explicit positive and negative personal ratings, while excluding titles already personally rated.
- Viewing Stats' schema-v2 JSON export includes personal ratings and title snapshots along with watch progress and history.
- Viewing Stats can import schema-v1/v2 backups after showing a count preview; merge keeps newer local progress/ratings, skips duplicate sessions, and never deletes current data.
- Catalog search matches alternate local titles and subtitles and shows an in-progress state until the remote lookup finishes.
- Embedded playback resumes from the saved point after reopening Denbox; position is persisted periodically and flushed on close.
- Watched time grows only while the embedded player reports active playback; opening the player without media progress must not create watched time.
- Episode progress survives API ID changes by using season/episode identity or a label/title fallback, without creating duplicate history rows.
- History, statistics, and recommendations refresh when a playback session ends or watch status changes.
- Viewing history remains local and can be exported or cleared by the user.

### Loading and discovery performance

- Opening the app shows cached catalog titles directly from SQLite. IMDb catalog enrichment stays in the background; it does not build the 30,000-title recommendation list or scan every IMDb genre at startup.
- The **For You** page loads the IMDb candidates on demand. The local IMDb dataset receives a partial rating-order index the first time discovery is requested; the candidate list and genre counts are cached in memory for later requests. On the installed 21.4 GB dataset, two measured first queries with the index present took 2.35–4.12 s for 30,000 candidates; repeated lookup was below 0.001 s. Genre counting took 0.94–1.13 s, and cached facet lookup was below 0.001 s. The index added about 49 MB when first created. An earlier cold measurement including index creation and query was 16.4 s.
- API detail/search routes race configured alternatives, catalog feed requests run concurrently, and feed request timeouts are shorter. The four performance/startup tests passed in optimized builds. The final app snapshot at `/tmp/denbox-final-push-20261016-r2` compiled and passed deep ad-hoc signature verification. Fourteen local tests passed; the live catalog test timed out after 60 seconds without a response.

Next product steps: manually verify personal-rating persistence, schema-v2 export/import merging, and search loading/results; visually verify language switching and right-to-left layout; exercise embedded playback controls, resume, pause/buffer accounting, audio/subtitle tracks, and the bundled libmpv runtime. Audit remaining dynamic status/error messages. Review runtime install names, signing, architecture, and redistribution/licensing before release. Check reference-metadata matching/cache behavior, the IMDb genre-index migration, and the live media API/download flow before publishing a release.

## Boundaries and risks

- Keep API credentials in Keychain; never place them in source, logs, screenshots, or this file.
- IMDb's downloaded dataset is documented by the project as personal, non-commercial use; keep its attribution and avoid bundling the data.
- The current app configuration allows arbitrary network loads because some media links use HTTP and redirect across hosts. Any transport tightening must account for those sources and be verified before changing it.
- Preserve the existing SQLite and Keychain locations during the Simba-to-Denbox rename so existing user data and credentials remain available.
- The README's build command currently targets Apple Silicon and macOS 13+ and creates an ad-hoc signed, non-notarized app.

## Cross-chat coordination

Use `AGENTS.md`, this file, `README.md`, and the current Git worktree as the shared source of truth across Denbox Codex chats. At the start of a Denbox task, read them and inspect `git status` and the relevant diff. Update this file when a product decision or a major workstream changes. The current chat tools do not expose a Codex chat index or other chat transcripts, so decisions that exist only in another conversation must be brought into the shared repo or pasted/linked by Sepehr.

Build coordination note for 2026-10-16: concurrent edits once caused `swiftc` to report a source file changed during compilation. A copied `Sources`/`Resources` snapshot with pre/post hash checks produced a clean build; use the source list in `README.md` (including `ReferenceMetadata.swift`) when validating later edits. This session has no Codex chat-list/read tools, and native app enumeration failed to start, so cross-chat decisions must continue through this file and the shared worktree.
