# LyricsApp Agent Guidance

## Scope and project shape

This repository contains two related products:

- `LyricsApp/` is the macOS SwiftUI reference app.
- `Packages/LyricsKit/` is the reusable Swift package and the home of metadata reading, filename parsing, LRCLIB access, matching, and lyrics parsing/resolution.

Keep the dependency direction one-way: `LyricsApp` may import `LyricsKit`; `LyricsKit` must not depend on the app or SwiftUI.

The current deployment and language baseline is Swift 6 with complete strict concurrency. The app targets macOS 15.6. `LyricsKit` supports macOS 15 and iOS 18.

## Architecture

Use this flow for feature work:

```text
User action
  -> SwiftUI view
  -> LyricsFinderViewModel action
  -> LyricsKit service or value-type helper
  -> Sendable result
  -> view-model presentation state
  -> SwiftUI view
```

### SwiftUI views

- Keep views focused on layout, styling, bindings, navigation/presentation, and short-lived interaction state.
- Views must not call networking, metadata readers, parsers, or other domain services directly.
- Send semantic actions to the view model rather than using `.onChange` to synchronize owners.
- Render typed display data prepared by the view model. Do not sort, filter, group, chunk, or format domain collections in `body`.
- Presentation strings derived from domain values belong in display models or the view model. In particular, do not add more timestamp or duration formatting inside a view.
- Give repeated display items stable identity from the domain object rather than an array index.
- Prefer a focused concrete `View` for a meaningful section, repeated content, or a section with its own dependencies/state. Small static fragments and local conditional routing may remain computed `some View` or `@ViewBuilder` properties.
- Child views should receive the smallest practical set of plain display values, bindings, and action closures. Do not give a child access to a service or engine.
- A view that creates an `@Observable` view model stores it with `@State`; a view that receives one uses a plain stored property. Introduce local `@Bindable` only where a control needs bindings.

### View models

- SwiftUI-observed view models are `@MainActor` and use the Observation framework (`@Observable`).
- View models own loading/content/empty/error state, typed display items, presentation strings, validation messages, and user-facing actions.
- Mark injected dependencies, task handles, caches, loggers, and other non-presentation bookkeeping with `@ObservationIgnored` where applicable.
- Keep one writable source of truth for each fact. Domain truth belongs in `LyricsKit` models/services; editable and derived presentation state belongs in the view model; ephemeral interaction state belongs in the view.
- A view model may cancel UI-owned work, but a service owns cancellation and cleanup for work/resources it starts.
- Apply asynchronous results to presentation state on the main actor and check cancellation before publishing stale results.

### LyricsKit services and models

- Keep domain behavior, file access, parsing, ranking, networking, pacing, and service errors in `LyricsKit`.
- Do not import SwiftUI or retain app view models in `LyricsKit`.
- Cross concurrency boundaries with small `Sendable` requests, results, snapshots, events, and IDs.
- Every mutable service owns its isolation. Prefer an `actor` for naturally serialized asynchronous state, as `LyricsLookupService` does. Do not use `@MainActor` merely to silence concurrency errors.
- Keep error information meaningful enough for the app to present or recover. Do not crash on user files, remote responses, or other recoverable runtime data.
- Reuse the shared package implementation instead of rebuilding domain behavior in the app. `AudioTrackMetadataResolver` is the shared metadata-plus-filename fallback path, and `LyricsContentResolver` is the shared synchronized/plain/instrumental/unavailable resolution path. When changing those flows, consolidate toward those types rather than creating another copy in `LyricsFinderViewModel`.
- Public `LyricsKit` API changes must update package tests and app callers together. Do not add backwards-compatibility shims or fallback paths unless the task explicitly requires them.

### Dependencies and ownership

- Construct long-lived services at the app or feature composition root and inject them into the view model.
- Keep default dependencies convenient for the reference app, while preserving injectable initializers for tests and previews.
- The code that creates a resource or task owns its cleanup. Cleanup must be explicit and safe to repeat.

## Swift style

Apply these rules to newly written or materially edited Swift. Preserve surrounding style and avoid unrelated formatting churn.

- Prefer explicit, imperative control flow and obvious, local mutation.
- Use `switch` when branching on one value. Use `if`/`else` for general branching; do not introduce `guard` merely for compactness.
- Avoid fluent chains when they hide mutation or side effects. Use descriptive intermediate values where they improve clarity.
- Do not create a helper function that is called only once in the same type merely to shorten its caller. Inline it unless it establishes a meaningful architecture, ownership, test, or view boundary.
- Do not add extensions to types owned by this repository. Extensions are reserved for types the project does not own, such as Foundation or standard-library types.
- Use underscore prefixes only when Swift requires them or for a private backing property exposed through a public getter.
- Use descriptive loop variables derived from their collections; do not abbreviate them as `vm`, `item`, or `obj`.
- Avoid semantic prepositions such as `from`, `with`, `using`, and `for` in external parameter labels. Encode the relationship in an explicit function name and use descriptive parameter names.
- Keep a one-parameter declaration or call on one line when it fits. Format declarations and calls with two or more parameters across multiple lines.
- Keep a single-line assignment on one line when the value fits.
- Brace placement is not worth standalone cleanup. Follow the surrounding file.
- Do not hand-tune formatting that an adopted formatter will rewrite. If `.swiftformat` is added, it becomes the source of truth for mechanical formatting; this file remains the source for semantic and architecture rules.

## Testing and verification

Add focused tests beside the behavior they protect. Pure parsing, fallback, matching, content resolution, and service-boundary behavior belong in `Packages/LyricsKit/Tests/LyricsKitTests/`.

From the repository root, run:

```sh
swift test --package-path Packages/LyricsKit
```

For app or integration changes, also build the Xcode scheme for macOS:

```sh
xcodebuild -project LyricsApp.xcodeproj -scheme LyricsApp -destination 'platform=macOS' build
```

Use narrower targeted tests while iterating, then run the full relevant package test suite before handing off. Keep production behavior testable through injected services and value boundaries; do not start real network or file work in SwiftUI previews.

## Before handing off Swift changes

- Confirm views contain presentation and local interaction only.
- Confirm reusable behavior lives in `LyricsKit`, not in a second app-only implementation.
- Confirm observable state is the smallest useful UI projection and non-UI bookkeeping is ignored by Observation.
- Confirm mutable services have explicit isolation and values crossing isolation are `Sendable`.
- Confirm branches, function count, names, parameter wrapping, loop names, and mutations follow the Swift rules above.
- Confirm user-data, cancellation, remote-error, empty, and retry paths remain coherent.
- Run the relevant package tests and app build, and report anything that could not be verified.

## Guidance intentionally not carried into this repository

The shared Swift source also contains rules for Metal render loops, shader/filter ownership, real-time frame scheduling, and physical iOS device builds. They do not apply to the current LyricsApp codebase. Add such guidance only if the repository gains those systems.
