# LyricsApp and LyricsKit

LyricsApp is the small reference app for finding lyrics for a local audio file. The importer accepts system-recognized audio formats, including MP3, M4A, AAC, CAF, WAV, AIFF, and compatible lossless formats. Its reusable implementation lives in the `LyricsKit` Swift package at `Packages/LyricsKit`.

## LyricsKit

LyricsKit supports macOS 15 and iOS 18. It provides:

- embedded audio metadata reading with filename fallback
- exact and search-based LRCLIB lookup
- independent LRCMÜX lookup with upstream-source attribution
- configurable LRCLIB-first or LRCMÜX-first provider priority
- up to five lookup attempts, with the second removing wrapped annotations throughout the title, artist, and album
- candidate ranking using track identity and duration
- synchronized LRC parsing
- synchronized, plain, instrumental, and unavailable content resolution
- a high-level lookup service with provider-specific cooldowns, fallback, request pacing, and rate-limit handling

Use `AudioTrackMetadataResolver` to identify a local track, `LyricsLookupService` to find a result or ranked candidates, and `LyricsContentResolver` to prepare the returned lyrics for presentation.

### Provider priority and fallback

`LyricsLookupService` uses LRCLIB first by default. Pass `preferredProvider: .lrcmux` to try LRCMÜX first instead. The preference changes lookup order; it does not disable fallback. A miss, unusable result, rate limit, or temporary failure from the preferred provider allows the independent provider to be tried next.

LRCMÜX requests explicitly exclude LRCLIB from LRCMÜX's own upstream sources, so the two attempts remain independent. Each provider also maintains its own rate-limit cooldown.

```swift
import LyricsKit

let input = LyricsMatchInput(
    title: "Song Title",
    artist: "Artist Name",
    album: "Album Name",
    duration: 181
)

let service = LyricsLookupService()
let outcome = try await service.findLyrics(
    input: input,
    requirement: .synchronized,
    preferredProvider: .lrcmux
)
```

Use `.any` when plain lyrics are acceptable, or `.synchronized` when the result must contain parseable timed lyrics. Instrumental results satisfy either requirement.

Every `LyricsResult` identifies its `provider`. LRCMÜX results can additionally include an `upstreamSource`, such as YouTube Music, for accurate attribution.

## LyricsApp reference app

The macOS example app imports a local audio file, lets the user review detected metadata, and exposes a persisted **Preferred Provider** selector. Search results show which provider ultimately supplied the lyrics. Changing the preference clears the displayed result so the next search uses the new order.

The LyricsApp project references `Packages/LyricsKit` directly. The package lives in its own directory to avoid Xcode workspace loading conflicts with `LyricsApp.xcodeproj` at the repository root.

Publishing LyricsKit as a remote dependency later requires a repository with this package at its root.

## Verification

Run the package tests from the repository root:

```sh
swift test --package-path Packages/LyricsKit
```

Build the macOS reference app from the repository root:

```sh
xcodebuild -project LyricsApp.xcodeproj -scheme LyricsApp -destination 'platform=macOS' build
```

## Example app


<img width="610" height="437" alt="image" src="https://github.com/user-attachments/assets/b9c682f0-44e1-4973-bcd6-d05ca6420426" />
