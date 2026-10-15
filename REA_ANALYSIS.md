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
