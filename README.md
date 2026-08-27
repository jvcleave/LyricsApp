# LyricsApp and LyricsKit

LyricsApp is the small reference app for finding lyrics for a local audio file. Its reusable implementation lives in the `LyricsKit` Swift package at `Packages/LyricsKit`.

## LyricsKit

LyricsKit supports macOS 15 and iOS 18. It provides:

- embedded audio metadata reading with filename fallback
- exact and search-based LRCLIB lookup
- candidate ranking using track identity and duration
- synchronized LRC parsing
- synchronized, plain, instrumental, and unavailable content resolution
- a high-level lookup service that applies request pacing and rate-limit handling

Use `AudioTrackMetadataResolver` to identify a local track, `LyricsLookupService` to find a result or ranked candidates, and `LyricsContentResolver` to prepare the returned lyrics for presentation.

The LyricsApp project references `Packages/LyricsKit` directly. The package lives in its own directory to avoid Xcode workspace loading conflicts with `LyricsApp.xcodeproj` at the repository root.

Publishing LyricsKit as a remote dependency later requires a repository with this package at its root.

## Verification

Run the package tests from the repository root:

```sh
swift test --package-path Packages/LyricsKit
```

The LyricsApp Xcode project also links the local package product, which keeps the reference app and package integration building together.
