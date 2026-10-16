# Denbox shared project context

Updated: 2026-10-16

## Goal and audience

Make Denbox Sepehr's best personal movie and TV app. The current product is a native macOS app, so work should stay Mac-first unless Sepehr changes that direction. Optimize for the daily loop: find something worth watching, start or resume it reliably, and remember what was watched. Keep viewing data local by default; avoid adding accounts, social features, or cloud collection without a clear personal-use need.

Confirmed preference: Persian is the default interface language for personal use. Preserve original/international film, series, person, and provider names. English remains available as an interface option. Persian localization is underway and must be described as partial until all user-facing screens and dynamic status messages are covered.

## Product baseline

See `README.md` for the source of truth on the current build and data boundaries. Existing capabilities include a SQLite catalog and My List, a direct media API, title and episode details, an embedded libmpv player, subtitle controls, offline downloads, and optional local IMDb data for charts, people, ratings, and episode matching.

Competitor references suggest useful patterns rather than a mandate to copy them: Letterboxd combines a film diary, watchlist, ratings, lists, and personal stats; JustWatch emphasizes title availability across services and tracking; Trakt defines playback scrobbling, watch history, watchlists, and favorites; Plex combines universal search and watchlists across providers. Sources: [Letterboxd FAQ](https://letterboxd.com/about/faq/), [JustWatch About](https://www.justwatch.com/us/about), [Trakt API guide](https://developer.trakt.tv/), [Plex Discover](https://www.plex.tv/discover/).

## Current product state

The current worktree implements local playback progress/history/statistics, genre preferences, and IMDb-based discovery in addition to the existing catalog, details, downloads, and player. On 2026-10-16 the current `Sources` and `Resources` snapshot was copied to a temporary directory, hash-matched against the worktree before the build, and verified unchanged after it. That exact snapshot built as an Apple Silicon macOS 13 app on macOS 26.2; deep ad-hoc code-signature verification passed for the app and bundled libraries. The compiler emitted OpenGL deprecation warnings. The app was not launched, playback was not manually exercised, and live API/range-download tests were not run. Earlier offline source-parser and IMDb episode-matcher tests passed on 2026-10-16; the newer reference-metadata tests have not been run.

- `LibrarySection` has `For You`, `Genres`, `Continue Watching`, `Watch History`, and `Viewing Stats`; `MainWindow` now routes to those pages.
- `MediaDatabase` has local watch-progress, watch-session, and genre-preference tables and read/write methods.
- `LibraryModel` now starts, updates, and finishes playback sessions; `LocalPlayerSheet` uses the embedded libmpv controller to save progress and resume from saved positions.
- IMDb-backed metadata and recommendation models now feed discovery and genre-filter views.
- Opening a title can fill missing detail fields through public Wikidata and TVmaze lookups, with source citations and a local SQLite cache. The lookup sends series/movie title terms or a matched IMDb ID; it does not include viewing history or My List. Movie title fallback requires a close title match and a film description in Wikidata; TVmaze data is marked with source attribution. The reference metadata tests passed on 2026-10-16; local shell probes could not reach the public metadata APIs in this environment. See `README.md` for source and cache details.
- Public title-page import from Filimo and HexDL is available on title details, with a review/edit step before saving locally; Filimo has precedence. Only allowlisted public title pages and visible page content are used. The new source files and Persian localization resource are included in the README build instructions.
- The app now has a saved interface-language preference defaulting to Persian, a Persian/English choice in Settings, right-to-left layout for Persian, and expanded translations for navigation, empty states, download states, dynamic catalog/API messages, IMDb import/charts, genre names, people roles, curated franchise descriptions, Settings, public-title import controls/review sheet/status, offline actions, and the embedded player's controls, track labels, and common errors. A static audit of literal SwiftUI labels across the main app, player, and public-page import found no missing Persian keys beyond the brand, system-symbol identifiers, and language names. Dynamic provider/OS/mpv error text still falls back to English, and visual RTL/language switching has not been manually checked.
- Genre and recommendation empty states distinguish a missing IMDb dataset from a ready dataset with no results; genre import now shows an in-progress state.
- `MPVPlaybackController` is now connected to the in-app player and reports progress directly to the watch-session model. Watched-time accounting treats mpv as actively playing only when it is not paused, idle, waiting for cache, seeking, or core-idle. This uses the corresponding mpv properties; playback and resume still need manual verification. The README build command copies libmpv and its runtime libraries from `/Applications/IINA.app/Contents/Frameworks`; this requires IINA installed at that path. The app bundle builds and passes deep ad-hoc signature verification, but runtime playback has not been exercised.
- The unused IINA-monitor path falls back to the last saved progress and duration if it finishes without a positive position snapshot; the current embedded player writes progress directly.
- Episode progress lookup tries the current API ID, then a stable season/episode label, then a unique title when the saved row has no label. When it finds an older row after an API ID change, playback keeps that stored ID to avoid duplicate progress rows.
- Viewing Stats can export all local progress and sessions as JSON, and clear both tables after confirmation. Clearing is disabled while a tracked player session is active; genre preferences remain intact.
- Offline title/episode lookup tolerates regenerated episode IDs by matching saved titles when needed.
- `IINAPlaybackMonitor` and its socket fixture remain in the worktree but are not used by the new in-app playback flow. The player uses direct libmpv events/properties instead. Keep the monitor's IPC security notes scoped to that unused path ([mpv IPC documentation](https://github.com/mpv-player/mpv/blob/master/DOCS/man/ipc.rst)).
- `Sources/MPVPlayback.swift` imports the `Sources/MPV` module map and IINA's libmpv runtime. The README now copies every `.dylib` from the installed IINA frameworks and links `libmpv.1.dylib`; review architecture compatibility, runtime install names, signing, and redistribution/licensing before any release.
- Reference-metadata lookups send a matched IMDb ID to Wikidata or a series title to TVmaze. They do not send viewing history or My List, and their result cache is local. Keep that boundary clear if adding providers.
- The libmpv package built and passed deep ad-hoc signature verification on this Apple Silicon Mac. The player currently renders through deprecated AppKit OpenGL APIs; investigate a supported libmpv rendering path for long-term macOS compatibility.

### Acceptance criteria for this workstream

- Every new sidebar section has a useful populated, loading, empty, and missing-IMDb-data state.
- Embedded playback resumes from the saved point after reopening Denbox; position is persisted periodically and flushed on close.
- Watched time grows only while the embedded player reports active playback; opening the player without media progress must not create watched time.
- Episode progress survives API ID changes by using season/episode identity or a label/title fallback, without creating duplicate history rows.
- History, statistics, and recommendations refresh when a playback session ends or watch status changes.
- Viewing history remains local and can be exported or cleared by the user.

Next product steps: audit remaining dynamic status/error messages; visually verify language switching and right-to-left layout. Exercise embedded playback, resume, pause/buffer accounting, audio/subtitle tracks, and the bundled libmpv runtime. Review runtime install names, signing, architecture, and redistribution/licensing before release. Check reference-metadata matching/cache behavior, the IMDb genre-index migration, and the live media API/download flow before publishing a release.

## Boundaries and risks

- Keep API credentials in Keychain; never place them in source, logs, screenshots, or this file.
- IMDb's downloaded dataset is documented by the project as personal, non-commercial use; keep its attribution and avoid bundling the data.
- The current app configuration allows arbitrary network loads because some media links use HTTP and redirect across hosts. Any transport tightening must account for those sources and be verified before changing it.
- Preserve the existing SQLite and Keychain locations during the Simba-to-Denbox rename so existing user data and credentials remain available.
- The README's build command currently targets Apple Silicon and macOS 13+ and creates an ad-hoc signed, non-notarized app.

## Cross-chat coordination

Use this file and the current Git worktree as the shared source of truth across Denbox Codex chats. At the start of a Denbox task, read this file, `README.md`, and `git status`; inspect the current diff before editing. Update this file when a product decision or a major workstream changes. The current chat tools do not expose a Codex chat index or other chat transcripts, so decisions that exist only in another conversation must be brought into the shared repo or pasted/linked by Sepehr.

Build coordination note for 2026-10-16: concurrent edits once caused `swiftc` to report a source file changed during compilation. A copied `Sources`/`Resources` snapshot with pre/post hash checks produced a clean build; use the source list in `README.md` (including `ReferenceMetadata.swift`) when validating later edits. This session has no Codex chat-list/read tools, and native app enumeration failed to start, so cross-chat decisions must continue through this file and the shared worktree.
