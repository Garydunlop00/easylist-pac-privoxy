# Crack Tracker (iOS)

A SwiftUI iPhone/iPad app that pulls crack status from public tracker sites and shows:

- **Uncracked**: released games with no crack yet, sorted by how long they've held out ("412d uncracked"). Upcoming releases are listed separately.
- **Cracked**: recent cracks with crack date, time to crack, scene group and DRM.
- **Watchlist**: star any game to get a **local notification when it gets cracked** (checked in the background every few hours, plus whenever you open the app).
- **Detail view**: a live "uncracked for 412d 05h 12m 09s" counter, each tracker's verdict side by side (with a warning when they disagree), DRM, groups, a Steam link and a link back to each tracker's page.
- **Sources**: turn trackers on or off, see which ones failed and why, edit their URLs, add new trackers, and add games by hand.

The app only reads status information. It doesn't host, link to or help anyone get pirated software.

## Trackers

| Tracker | Default URL(s) | Notes |
|---|---|---|
| CrackWatch | `crackwatch.com` (WebView) + the legacy `api.crackwatch.com` JSON API | The original API was shut down. It stays as a fallback for mirrors that use the same schema. |
| CrackRelease | `crackrelease.com` | |
| IsItCracked | `isitcracked.com` (WebView) | |
| GameStatus | `gamestatus.info/back/api/...` | Extra JSON source |

**Important:** these sites change layouts and APIs often, and many sit behind Cloudflare. The parsers were written without live access to the sites, so treat the default URLs as starting points. If a tracker shows a red ✗ in **Sources**:

1. Open it and tap **Test this tracker** to see the error.
2. Turn on **Render JavaScript (WebView)** for sites that build their pages with JavaScript or show "checking your browser" pages.
3. Swap in a better URL. A JSON API endpoint (find it in Safari/Chrome dev tools → Network) is the most reliable choice.

### How parsing works (`Sources/GameExtractor.swift`)

There's no hard-coded scraper per site. For any URL the extractor:

- **JSON**: walks the whole response and picks out objects that look like a game. That means a title plus at least one of: release date, crack date, crack flag, status text, groups or DRM. It understands common key spellings (`crackDate`, `crack_date`, `hacked_groups`, `is_cracked`, `readable_status`, `protections`, `steam_prod_id`, …). Wrapper keys such as `uncracked_games` or `recentlyCracked` set the status for everything inside them.
- **HTML**: reads embedded JSON (`__NEXT_DATA__`, JSON-LD, inline JSON) and any `<table>` whose header row has a game/title column plus release, crack date, status, group or DRM columns.
- **Status rules**: an explicit flag or status text wins. Next comes "has a crack date → cracked", then the endpoint's *Games on this page are…* setting, then "has an empty crack-date field → uncracked".

Games are merged across trackers by normalised title (case, accents, ™/®, apostrophes and `&`/`and` are ignored). If any tracker reports a crack, the game counts as cracked.

## Building

Requirements: macOS with Xcode 15 or later and an iOS 17 device or simulator.

```sh
brew install xcodegen
cd CrackTracker
xcodegen generate
open CrackTracker.xcodeproj
```

Choose your team under *Signing & Capabilities* (and change the bundle ID from `com.example.cracktracker` if you like), then run. Unit tests for the parser are in `CrackTrackerTests` (⌘U).

Without XcodeGen: create a new iOS App project in Xcode named `CrackTracker` (SwiftUI, iOS 17) and drag in the `CrackTracker/` folder. Then add the *Background Modes → Background fetch* capability, and add `$(PRODUCT_BUNDLE_IDENTIFIER).refresh` under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.

> Distribution: Apple may reject piracy-adjacent apps from the App Store. Installing from Xcode on your own device (free account: re-sign every 7 days) or using TestFlight is the practical route.

## Layout

```
CrackTracker/
  App/CrackTrackerApp.swift        app entry, background refresh
  Models/Game.swift                SourceReport (per tracker) and Game (merged)
  Sources/SourceConfig.swift       tracker definitions and default URLs
  Sources/SourceFetcher.swift      downloading, pagination ({page}/{page0}), errors
  Sources/WebPageRenderer.swift    off-screen WKWebView for JS-rendered sites
  Sources/GameExtractor.swift      schema-agnostic JSON/HTML extraction
  Store/GameStore.swift            refresh, merge, watchlist, persistence
  Store/Notifier.swift             notifications and BGAppRefresh scheduling
  Util/                            title normalisation, date parsing, formatting
  Views/                           SwiftUI screens
CrackTrackerTests/                 parser and merge tests
```
