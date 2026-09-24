# Ororo for Apple TV

A native tvOS client for [ororo.tv](https://ororo.tv), signed in with your own
Ororo account.

- **Home** with Continue Watching, My List, new episodes, popular shows and
  genre rows
- **Search** across every show and movie, as you type
- **TV Shows** and **Movies** grids with sort order and genre filter
- **Watch history**: resumes where you stopped, marks episodes watched and
  plays the next episode automatically
- **My List** for saving shows and movies
- **Dual subtitles**: pick a main subtitle language and a second one shown
  above it, from Settings or the player's transport bar

## Build and run

You need a Mac with Xcode 15 or later and
[XcodeGen](https://github.com/yonaskolb/XcodeGen), which generates the Xcode
project from `project.yml`.

```sh
brew install xcodegen
xcodegen generate
open OroroTV.xcodeproj
```

In Xcode, select the **OroroTV** target, open **Signing & Capabilities** and
choose your team. A free Apple ID works for running on your own Apple TV.
Then run on an Apple TV simulator, or on a real Apple TV paired with Xcode
(on the Apple TV: Settings > Remotes and Devices > Remote App and Devices).

Run `xcodegen generate` again after adding or removing files.

## Layout

```
project.yml            XcodeGen spec for the tvOS app
OroroTV/               The tvOS app (SwiftUI)
  App/                 Entry point, AppModel (session, catalog, library), Keychain
  Views/               Home, Search, Browse, My List, show/movie detail, Settings
  Player/              AVPlayerViewController wrapper, subtitle overlay and menu
Packages/OroroKit/     Platform-independent core, unit-tested
  OroroClient.swift    API client: Basic auth, mirror fallback, ETag revalidation
  Models.swift         API models
  SearchIndex.swift    Local search over the catalog
  WebVTT.swift         Subtitle parser
  Library.swift        Watch history and My List
docs/API.md            What the Ororo API looks like
```

## How it works

- **Catalog.** The API has no search or paging, so the app downloads the whole
  show and movie lists (about 12,000 titles) and keeps them in the Caches
  directory. On later launches it revalidates them with ETags, which costs a
  `304` instead of several megabytes when nothing changed.
- **Playback.** Stream URLs are signed and expire, so the player fetches a
  fresh one each time. Video plays in the native tvOS player.
- **Subtitles.** Ororo's streams carry no subtitle tracks, so the player
  downloads the WebVTT files and draws them itself. That is also what makes
  two languages at once possible.
- **History and My List** are stored on the Apple TV in `UserDefaults`. tvOS
  only guarantees an app about 500 KB of storage that won't be purged, so the
  store keeps IDs and positions only (well under 100 bytes per title) and caps itself
  at 2,000 entries.
- **Sign-in.** Your email and password are kept in the Keychain and sent to
  Ororo over HTTPS with each request.

### Limitations

- History and My List are not synced with the ororo.tv website or between
  devices. Ororo's API has no endpoint for them.
- Free accounts hit Ororo's daily limit (30 minutes); the app shows Ororo's
  message when that happens.

## Tests

The core package builds and tests on macOS or Linux:

```sh
cd Packages/OroroKit
swift test
```

Tests against the live API are skipped unless you provide an account:

```sh
ORORO_EMAIL=you@example.com ORORO_PASSWORD=... swift test --filter LiveAPITests
```
