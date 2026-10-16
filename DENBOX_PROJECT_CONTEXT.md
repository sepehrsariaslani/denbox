# Denbox shared project context

Updated: 2026-10-16

## Goal and audience

Make Denbox Sepehr's best personal movie and TV app. The current product is a native macOS app, so work should stay Mac-first unless Sepehr changes that direction. Optimize for the daily loop: find something worth watching, start or resume it reliably, and remember what was watched. Keep viewing data local by default; avoid adding accounts, social features, or cloud collection without a clear personal-use need.

## Product baseline

See `README.md` for the source of truth on the current build and data boundaries. Existing capabilities include a SQLite catalog and My List, a direct media API, title and episode details, AVKit playback with IINA fallback, subtitle controls, offline downloads, and optional local IMDb data for charts, people, ratings, and episode matching.

Competitor references suggest useful patterns rather than a mandate to copy them: Letterboxd combines a film diary, watchlist, ratings, lists, and personal stats; JustWatch emphasizes title availability across services and tracking; Trakt defines playback scrobbling, watch history, watchlists, and favorites; Plex combines universal search and watchlists across providers. Sources: [Letterboxd FAQ](https://letterboxd.com/about/faq/), [JustWatch About](https://www.justwatch.com/us/about), [Trakt API guide](https://developer.trakt.tv/), [Plex Discover](https://www.plex.tv/discover/).

## Current product state

The current worktree implements local playback progress/history/statistics, genre preferences, and IMDb-based discovery in addition to the existing catalog, details, downloads, and player. The current source built successfully on macOS 26.2 for the Apple Silicon macOS 13 target. The offline source parser and IMDb episode matcher tests passed on 2026-10-16; live API and range-download tests were not run.

- `LibrarySection` has `For You`, `Genres`, `Continue Watching`, `Watch History`, and `Viewing Stats`; `MainWindow` now routes to those pages.
- `MediaDatabase` has local watch-progress, watch-session, and genre-preference tables and read/write methods.
- `LibraryModel` now starts, updates, and finishes playback sessions; `LocalPlayerSheet` sends AVPlayer progress snapshots and resumes from saved positions.
- IMDb-backed metadata and recommendation models now feed discovery and genre-filter views.
- IINA receives the saved start position, and Denbox closes its session immediately after launch. IINA does not report ongoing playback position or watched time back to Denbox, so activity tracking during IINA playback is incomplete.
- Offline title/episode lookup tolerates regenerated episode IDs by matching saved titles when needed.

### Acceptance criteria for this workstream

- Every new sidebar section has a useful populated, loading, empty, and missing-IMDb-data state.
- AVPlayer playback resumes from the saved point after reopening Denbox; position is persisted periodically and flushed on close.
- Watched time grows only during actual embedded playback. IINA opens must not create phantom sessions unless the app gains reliable IINA playback events.
- Episode progress survives API ID changes by using season/episode identity or a label/title fallback, without creating duplicate history rows.
- History, statistics, and recommendations refresh when a playback session ends or watch status changes.
- Viewing history remains local and can be exported or cleared by the user.

Next product steps: add reliable IINA playback tracking if its IPC lifecycle can be maintained safely; add local export and clear controls for viewing history; test the IMDb genre-index migration and live media API/download flow before publishing a release. Keep IINA sessions from being counted as watched merely because the player launched.

## Boundaries and risks

- Keep API credentials in Keychain; never place them in source, logs, screenshots, or this file.
- IMDb's downloaded dataset is documented by the project as personal, non-commercial use; keep its attribution and avoid bundling the data.
- The current app configuration allows arbitrary network loads because some media links use HTTP and redirect across hosts. Any transport tightening must account for those sources and be verified before changing it.
- Preserve the existing SQLite and Keychain locations during the Simba-to-Denbox rename so existing user data and credentials remain available.
- The README's build command currently targets Apple Silicon and macOS 13+ and creates an ad-hoc signed, non-notarized app.

## Cross-chat coordination

Use this file and the current Git worktree as the shared source of truth across Denbox Codex chats. At the start of a Denbox task, read this file, `README.md`, and `git status`; inspect the current diff before editing. Update this file when a product decision or a major workstream changes. The current chat tools do not expose a Codex chat index or other chat transcripts, so decisions that exist only in another conversation must be brought into the shared repo or pasted/linked by Sepehr.
