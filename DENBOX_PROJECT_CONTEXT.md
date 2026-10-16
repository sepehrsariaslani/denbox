# Denbox shared project context

Updated: 2026-10-16

## Goal and audience

Make Denbox Sepehr's best personal movie and TV app. The current product is a native macOS app, so work should stay Mac-first unless Sepehr changes that direction. Optimize for the daily loop: find something worth watching, start or resume it reliably, and remember what was watched. Keep viewing data local by default; avoid adding accounts, social features, or cloud collection without a clear personal-use need.

Confirmed preference: Persian is the default interface language for personal use. Preserve original/international film, series, person, and provider names. English remains available as an interface option. Persian localization is underway and must be described as partial until all user-facing screens and dynamic status messages are covered.

## Product baseline

See `README.md` for the source of truth on the current build and data boundaries. Existing capabilities include a SQLite catalog and My List, a direct media API, title and episode details, an embedded libmpv player, subtitle controls, offline downloads, and optional local IMDb data for charts, people, ratings, and episode matching.

Competitor references suggest useful patterns rather than a mandate to copy them: Letterboxd combines a film diary, watchlist, ratings, lists, and personal stats; JustWatch emphasizes title availability across services and tracking; Trakt defines playback scrobbling, watch history, watchlists, and favorites; Plex combines universal search and watchlists across providers. Sources: [Letterboxd FAQ](https://letterboxd.com/about/faq/), [JustWatch About](https://www.justwatch.com/us/about), [Trakt API guide](https://developer.trakt.tv/), [Plex Discover](https://www.plex.tv/discover/).

## Current product state

The product includes local playback progress/history/statistics, genre preferences, IMDb discovery, title details, downloads, and the embedded player. Earlier on 2026-10-16, commit `a21c0e1` was installed as version 0.2.6 (build 8) at `/Users/sepehr/Library/Application Support/MacDupl/c/42505fb2/Home/Applications/Denbox.app`; it launched, loaded bundled libmpv/FFmpeg, and rendered a synthetic local MP4. Live movie and episode source probes opened in embedded libmpv. A later hash-checked snapshot of the current `Sources` and `Resources` compiled as an Apple Silicon macOS 13 app on macOS 26.2, and deep ad-hoc signature verification passed. A current-worktree hash comparison confirmed those source/resource files still match that built snapshot. That snapshot has not been installed; the installed build remains 0.2.6 (build 8). The latest compile emitted 129 warning lines, all from deprecated OpenGL APIs. Tests were not run during that compile. The worktree includes the My Ratings page, local rating-based recommendations, and schema-v2 viewing-data export. Database persistence, export contents, and recommendation behavior still need runtime verification. Earlier checks passed for offline database persistence, source parsing, embedded-player initialization, and segmented downloads; playback controls, resume after relaunch, and offline playback still need a complete UI walkthrough. The current public metadata provider path remains unverified because shell TLS probes could not reach those services.

- `LibrarySection` has `For You`, `Genres`, `Continue Watching`, `Watch History`, `Viewing Stats`, and `My Ratings`; `MainWindow` routes to these pages.
- `MediaDatabase` has local watch-progress, watch-session, and genre-preference tables and read/write methods.
- Personal movie and series ratings use a separate local one-to-five-star table. Each rating keeps a title snapshot, appears on poster cards and in the My Ratings sidebar page, and can be changed or cleared independently of IMDb's score. For You uses star-rating affinity for genres and excludes titles already rated; a later IMDb import updates a saved rating's title snapshot so its IMDb identity and genres remain available. Persian and English labels are included. The hash-checked Apple Silicon/macOS 13 snapshot compiled and passed deep ad-hoc signature verification on 2026-10-16; database persistence and recommendation behavior still need runtime verification.
- **For You** now uses private star ratings as a taste signal alongside local watch history and chosen genres, and leaves already-rated titles out of the recommendation list. When IMDb enrichment later supplies a missing IMDb ID or genres, the saved rated-title snapshot is refreshed without changing its rating date. Searching My Ratings stays local and does not call the media API.
- Viewing Stats' schema-v2 JSON export now includes personal ratings and their catalog snapshots with watch progress and session history, so a user's local rating collection is portable from the app.
- `Tests/PersonalRatingPersistenceTests.swift` is present in the shared worktree for save, reload, update, range-check, and clear behavior. The latest app compile did not execute that test.
- `LibraryModel` now starts, updates, and finishes playback sessions; `LocalPlayerSheet` uses the embedded libmpv controller to save progress and resume from saved positions.
- IMDb-backed metadata and recommendation models now feed discovery and genre-filter views.
- Catalog loading and pagination now start a bounded background pass across every locally loaded movie and series. Wikidata and TVmaze fill missing detail fields, with source citations and a local SQLite cache; title details still trigger a lookup if they are opened before the catalog pass reaches them. Wikidata now attempts strict title/type matching for series even when there is no IMDb ID. Lookups send title terms or a matched IMDb ID; they do not include viewing history or My List. Filimo/HexDL still require a public title URL and review/save step. The current live provider request path remains unverified in this environment because shell TLS probes could not validate the network certificate. See `README.md` for source and cache details.
- Public title-page import from Filimo and HexDL is available on title details, with a review/edit step before saving locally; Filimo has precedence. Only allowlisted public title pages and visible page content are used. The new source files and Persian localization resource are included in the README build instructions.
- The app now has a saved interface-language preference defaulting to Persian, a Persian/English choice in Settings, right-to-left layout for Persian, and expanded translations for navigation, empty states, download states, dynamic catalog/API messages, IMDb import/charts, genre names, people roles, curated franchise descriptions, Settings, public-title import controls/review sheet/status, offline actions, and the embedded player's controls, track labels, and common errors. A static audit of literal SwiftUI labels across the main app, player, and public-page import found no missing Persian keys beyond the brand, system-symbol identifiers, and language names. Dynamic provider/OS/mpv error text still falls back to English, and visual RTL/language switching has not been manually checked.
- Genre and recommendation empty states distinguish a missing IMDb dataset from a ready dataset with no results; genre import now shows an in-progress state.
- `MPVPlaybackController` is now connected to the in-app player and reports progress directly to the watch-session model. Watched-time accounting treats mpv as actively playing only when it is not paused, idle, waiting for cache, seeking, or core-idle. Standalone local rendering and live movie/episode source-opening probes passed; full controls, saved resume after relaunch, and offline playback still need a manual walkthrough inside the installed app. The README build command copies libmpv and its runtime libraries from `/Applications/IINA.app/Contents/Frameworks`; this requires IINA installed at that path.
- The unused IINA-monitor path falls back to the last saved progress and duration if it finishes without a positive position snapshot; the current embedded player writes progress directly.
- Episode progress lookup tries the current API ID, then a stable season/episode label, then a unique title when the saved row has no label. When it finds an older row after an API ID change, playback keeps that stored ID to avoid duplicate progress rows.
- Viewing Stats exports watch progress, session history, personal ratings, and their title snapshots as schema-v2 JSON. Clearing watch history removes progress and sessions after confirmation, while personal ratings and genre preferences remain intact.
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
- Embedded playback resumes from the saved point after reopening Denbox; position is persisted periodically and flushed on close.
- Watched time grows only while the embedded player reports active playback; opening the player without media progress must not create watched time.
- Episode progress survives API ID changes by using season/episode identity or a label/title fallback, without creating duplicate history rows.
- History, statistics, and recommendations refresh when a playback session ends or watch status changes.
- Viewing history remains local and can be exported or cleared by the user.

Next product steps: manually verify personal-rating persistence and schema-v2 export contents; visually verify language switching and right-to-left layout; exercise embedded playback controls, resume, pause/buffer accounting, audio/subtitle tracks, and the bundled libmpv runtime. Audit remaining dynamic status/error messages. Review runtime install names, signing, architecture, and redistribution/licensing before release. Check reference-metadata matching/cache behavior, the IMDb genre-index migration, and the live media API/download flow before publishing a release.

## Boundaries and risks

- Keep API credentials in Keychain; never place them in source, logs, screenshots, or this file.
- IMDb's downloaded dataset is documented by the project as personal, non-commercial use; keep its attribution and avoid bundling the data.
- The current app configuration allows arbitrary network loads because some media links use HTTP and redirect across hosts. Any transport tightening must account for those sources and be verified before changing it.
- Preserve the existing SQLite and Keychain locations during the Simba-to-Denbox rename so existing user data and credentials remain available.
- The README's build command currently targets Apple Silicon and macOS 13+ and creates an ad-hoc signed, non-notarized app.

## Cross-chat coordination

Use `AGENTS.md`, this file, `README.md`, and the current Git worktree as the shared source of truth across Denbox Codex chats. At the start of a Denbox task, read them and inspect `git status` and the relevant diff. Update this file when a product decision or a major workstream changes. The current chat tools do not expose a Codex chat index or other chat transcripts, so decisions that exist only in another conversation must be brought into the shared repo or pasted/linked by Sepehr.

Build coordination note for 2026-10-16: concurrent edits once caused `swiftc` to report a source file changed during compilation. A copied `Sources`/`Resources` snapshot with pre/post hash checks produced a clean build; use the source list in `README.md` (including `ReferenceMetadata.swift`) when validating later edits. This session has no Codex chat-list/read tools, and native app enumeration failed to start, so cross-chat decisions must continue through this file and the shared worktree.

### Installed app state

On 2026-10-16, the hash-checked source snapshot `620409938ae4c601e111d91b8ff42696e4188b5ad40ce2760a88d0385caa2ef0` built as an Apple Silicon macOS 13 app and passed deep ad-hoc signature verification. It was installed at `/Users/sepehr/Library/Application Support/MacDupl/c/42505fb2/Home/Applications/Denbox.app` at 04:59 local time. Existing process 91602 was left running, so the installed bundle has the update but that process continues to run its already-loaded version until restarted. Reference metadata parsing/cache and personal-rating persistence tests passed against the same source snapshot. Live public-provider requests and a post-install UI session were not verified.
