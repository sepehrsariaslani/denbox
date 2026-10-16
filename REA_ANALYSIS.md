# APK analysis notes

## Artifact and method

- Input: `/Users/sepehr/Downloads/Simba-v79.apk`
- SHA-256: `c3c38815e5cebf02a4f6060e0cd563e2d6680da297ebb05cf93de90d5a2eb4d2`
- REA/JADX package inspection: package `com.codegraphi.simba2`, version `1.0.0`, min SDK 21, target SDK 36.
- The APK contains about 17,866 classes and names its principal application code under `ir.filimo.*`.
- APK execution and signature verification were not performed.

REA's Android class and method inventory identified `ir.filimo.api.apiRest` as a Retrofit interface, `ir.filimo.api.apiClient` as its client builder, `ir.filimo.config.Config` as the base-URL accessor, and `ir.filimo.api.apiURL` as the config loader. The home response model contains poster, slide, genre, channel, actor, country, and related collections. A poster model carries title, image/cover, description, year, rating, type, and playback source fields.

The interface declares catalog, search, movie/series detail, season, login, account, comment, purchase, and download-related calls. Example route shapes observed in the interface include `first/{route-key}/`, `search/{query}/{route-key}/`, `movie/by/{id}/{route-key}/`, and `season/by/serie/{id}/{route-key}/`. Values used as route keys and other bundled credentials have been omitted from this repository and are not copied into the Mac app.

## Network boundary

The Retrofit base URL is read from a downloaded configuration file, rather than being fixed in the app. Static code shows the APK fetching that file over plain HTTP; the manifest also permits cleartext traffic. For the Mac build, the same config file was fetched over HTTPS (without an API key) and returned the current host `ninwinios.info`. Simba now calls that host through HTTPS as `ninwinios.info/api`. Its `first/{key}` response contains metadata collections and an empty `channels` list, so movie and series catalog rows continue to come from the separate HTTPS feeds.

## Direct API implementation from `denflow`

The Mac app uses the separate API setup present in the user-provided `denflow` source, rather than Frappe routes or the APK's undocumented service. The source defines movie and series catalog feeds on `rubyxpin.info`, a search API on `gitcss.info`, and movie/series detail routes on `gitcss.info`. Their credentials are read from that local source and stored in macOS Keychain; no credential values are embedded in the app or this document.

The catalog feeds, search endpoint, and a movie detail request were contacted over HTTPS. The feeds returned 30 rows each and the detail response included source metadata. Playback URLs are HTTP-only: a range request to a current source redirected from `dl175m.info` to `gooyaserver.com` and returned HTTP 206; upgrading that source to HTTPS failed certificate validation. For this personal build, ATS is now disabled globally so AVKit can follow plain-HTTP sources and redirects from any host. API calls in the app still use HTTPS. This broad setting reduces security for every network connection made by the app. Simba caches catalog records and its local My List in SQLite under the user's Application Support directory. It does not bypass authentication, subscriptions, DRM, or player restrictions.

The app does not call Frappe endpoints. Its source contains only the API route shapes and Keychain lookups, not the user's API keys.

## Evidence and limits

The package, class inventory, signatures, and selected method bodies were examined with REA using the supplied JADX headless engine. JADX's abstract Retrofit method view did not include method annotations, so the exact annotation shapes above were read from the same local JADX engine's class output as a supplemental static view. APK observations are from the supplied artifact and do not prove endpoint availability. The separate `denflow` API availability was checked with sanitized response summaries; response URLs, credentials, and media links were not printed.

## Public Filimo and HexDL metadata pages (REA)

- REA browser inspection confirmed Filimo's visible `/search` page, its client-rendered search control, and matching title pages under `/m/<id>`. HexDL exposes a public search modal from its home page and renders title results as public title pages. The search interface is dynamic, so the app waits for rendered controls/results rather than assuming the initial HTML contains the catalog.
- Denbox repeats that visible search flow in a non-persistent WebKit view for loaded movie and series catalog entries in a one-title-at-a-time background queue, and again when a detail page opens. A normalized-title similarity threshold plus year/type checks filters results; it then stores visible Persian synopsis, poster URL, headings, episode text, and the public page URL in the existing SQLite database. Complete records refresh after 30 days; empty or incomplete lookups use a 24-hour cooldown. The detail and Settings actions can force a new lookup.
- The importer does not sign in or read player, stream, or download links. Simba's existing API remains the only media playback/download source. Static APK inspection found Simba API classes but no HexDL-named integration; HexDL is therefore handled as a separate public metadata site, not as an APK endpoint.
- A standalone WebKit smoke found the public Shahrzad page on both Filimo and HexDL and returned Persian descriptions and images. This confirms that the public-page lookup works for that sample; it does not guarantee a match or coverage for every title. Full SwiftUI interaction remains a separate runtime check.

## IINA macOS player analysis (REA)

- Reference executable: `/Applications/IINA.app/Contents/MacOS/IINA`.
- The executable is universal. REA's Ghidra 12.1.4 analysis used a temporary arm64-only copy at `/tmp/IINA-arm64-for-REA`; its SHA-256 was `98fd1521817c7da21a71eb45ff008e66d5b01a3210aa43ff299e871180bb68df`. The installed IINA bundle was not modified.
- Static analysis found IINA's player built on libmpv with an OpenGL renderer. Its `MPVController.mpvInit` sets up libmpv, configuration/input paths, watch-later, subtitle, hardware-decode, and OSD options.
- `PlayerCore.loadExternalSubFile` adds an external subtitle with mpv's `sub-add` command, recognizes an already-loaded path, and applies optional delay. Its screenshot path issues `screenshot-to-file`, choosing video-only or subtitle-composited output from the user's preference.
- IINA's crop handler calculates a centered crop from source dimensions and adds a named `iina_crop` video filter; aspect changes use mpv's video-aspect property. Other recovered player actions cover video/audio/subtitle tracks, external audio, subtitle reload/delay, audio delay, speed, rotation, chapters, playlist/loop, A–B loop, audio EQ, video/audio filters, and playback history.
- Selected REA evidence: `MPVController.mpvInit` `ev_0b9a3451d47ba67afbd6454a5bd875f692b2174b8ef5ed4ffad19412125bde99`; external subtitles `ev_ccde0d19a03e3cb2e5fb5218f127aa89e69f61aebf7640efe26f975100489eaf`; screenshot `ev_c3fddbd53bac869fae45879f84bc8bc8dadfae7049acee685b8d8b6cf8222d0d`; crop `ev_d5693e74792989f262bf475cb97265b5c0c95793cc55a86d829109a5b967b7ff`; aspect `ev_2006cbee8b37e27072630e1a54ae5bcf4b0e5aa01283ee8dd9380e0dc17fcfda`; audio delay `ev_9dd40255fe5de2e33c3c7f8dbe592b9d5a31b6dbe43134bbbde3c4b2049fc030`; speed `ev_56e2079bc4ccd9f53fafb196f83bedd2de2534a7dbf4d7622ee5a5b2fe4fb511`.
- Additional REA procedures exposed IINA's PiP flow: `MainWindowController.enterPIP` reuses the player video view, passes it to the PiP controller, preserves the playing state and title, and invokes `presentViewControllerAsPictureInPicture` (`ev_2e21e996c37540291fb44a1a905c6c722df0ab8ca46d50705d36cc0d65a21424`). Online subtitle search routes through `menuFindOnlineSub` and has concrete `ShooterSubtitle`, `OpenSubSubtitle`, and `AssrtSubtitle` download implementations (`ev_b48552e1da2889a0c998e3cb094f397f830ca1ae5154c2bed4390e8549b70797`; search UI path `ev_57542b0cd8b2633eb34e72eb443d0c5805e6a326ddc39ca274c642d718dd50f0`). The audio output picker asks mpv for `audio-device-list`, parses its node maps and frees the node contents, then exposes the devices through IINA's menu (`ev_15955d6455e17da6baeb507a04af366e44efbdbd928dd64fbbcd1d09861ec8ea`; menu methods `ev_5df9f573f787449b690d8d65742b67117d39bb8424495142e637af66dd7a0d36`). Denbox now reads the same mpv property and lets the user select an output device; PiP and online subtitle search remain missing.

These are static findings, not proof of a live IINA UI walkthrough. After Accessibility was enabled, CUA's native pipe still failed to start; REA's native UI observer also failed to bind its selected CG window to a unique Accessibility window. A direct window screenshot did show Denbox rendering a live stream in its embedded player; it does not verify PiP, a fullscreen transition, or prolonged buffering behavior. Denbox implements recovered behavior through its own libmpv controller; it does not copy IINA code. PiP, online subtitle search/download, custom mpv scripts/input configuration, and some advanced media-source features remain open parity work.
