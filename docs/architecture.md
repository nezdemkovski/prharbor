# PR Harbor architecture

## Source layout

The Xcode project uses synchronized folders: a file joins its target by being in the folder. Each file holds one component and the small private types only it uses.

- `App/`: app lifetime, the status item and popover, runtime, the service graph and the About window.
- `Preferences/`: preference keys, their option types, the `PullRequestSettings` snapshot the store reads, and the preferences domain.
- `DesignSystem/`: `DesignTokens` and `Components/`, the panel's controls as SwiftUI styles over system buttons and toggles (`SegmentedControl`, `ChipToggleStyle`, `PrimaryButtonStyle`, `IconButtonStyle`, `TintedButtonStyle`). Screens use these instead of styling a plain button in place, so hover, press, disabled and accessibility behave the same everywhere.
- `Models/GitHub/`: GraphQL payload types by area (pull request, stack, checks, history, responses), `GitHubEnums`, and how check results become a CI status.
- `Models/Timeline/`: what the panel derives from a pull request: `TimelineItem`, `NextAction`, freshness, scale, events, sources, bot matching, snooze policy and `TimelinePresentation`.
- `Models/Intelligence/`: what Apple Intelligence receives: the search context and the morning brief snapshot.
- `Services/GitHub/`: transport, token storage and connection, the client and `GitHubQueries`, every GraphQL document it sends.
- `Services/Store/`: `PullRequestStore` and the pieces it coordinates: `PullSearch`, `SnapshotStorage` over `PullSnapshotCache`, `RefreshSchedule` and `PreferenceObserver`.
- `Services/Notifications/`: permission, change tracking between refreshes, the policy for what to announce, and delivery.
- `Services/Intelligence/`, `Services/Avatars/`: on-device model calls, and downscaled avatar loading with a shared cache.
- `Views/Timeline/`: the panel. `Header/` (search and controls), `Rows/`, `Drawing/` (axis, grid, track, hatching), `Detail/`, `Scrolling/` (the AppKit virtual scroll view), `Screen/` (the screen controller and its state), `Preview/`, plus the morning brief and empty state.
- `Views/Settings/`: the settings window, one file per pane. `Views/Avatar/`: avatar views.

Code is formatted with `swift format` using `.swift-format`; CI fails on any difference:

```bash
swift format format --in-place --recursive PRHarbor PRHarborTests
```

## Responsibilities

- `AppDelegate` owns menu bar and settings window lifetime. `StatusBarController` owns the status item and popover. `AppRuntime` prevents hosted tests from starting production services; `AppPreferences` supplies either the existing preference domain or a fresh test suite. Debug and Release both run as a menu bar accessory without a Dock icon; the preview window opens only with `PRHARBOR_PREVIEW=1` or `PRHARBOR_DEBUG_WINDOW=1`.
- `GitHubSession` owns the connected account, its Keychain-stored personal access token and the connection generation. `GitHubHTTPTransport` is the transport boundary: authorized HTTPS requests to the REST `user` endpoint and GraphQL, with token, rate-limit and HTTP failures mapped to `GitHubAccessError`. `GitHubClient` builds and decodes GitHub requests, carries the connected login and verifies it against `viewer` in each search. `GitHubTokenConnector` validates a pasted token and its classic scopes before it is stored.
- `PullRequestStore` owns refresh cancellation/generations, progressive category results and side effects; it delegates searches to `PullSearch`, cache ordering to `SnapshotStorage`, timers to `RefreshSchedule` and preference changes to `PreferenceObserver`. Stack mutation uses its injected client provider and forces revalidation after any mutation attempt that could have completed layers. Account/scope changes invalidate old work.
- `TimelineInput` projects category data into deduplicated `TimelineItem` values, preserving review-request membership even when another category supplies the visible item. Store counters, settings samples and the screen use this projection.
- `TimelineNotificationPolicy` and `TimelineSnoozePolicy` make pure decisions. `PullNotificationCoordinator` applies the notification policy after each refresh and posts through `NotificationDelivery`; the store writes snooze changes.
- `TimelineScreenController` owns tab, filter, selection, collapse and asynchronous search interpretation. It publishes one immutable snapshot containing the matching presentation, selected item, brief, brush and search state. Keyboard selection reuses the cached presentation. Focus, hover, pointer gestures and scrolling stay in the view.
- `TimelinePresentation` groups and orders rows and supplies navigation/ranges. `TimelineRowGeometry` defines the sizing contract used by both presentation and rendered rows. `TimelineNativeScrollView` mounts the visible/prefetch host set with incremental scroll preparation; tab replacement prepares visible rows synchronously.

## Timeline rendering

`TimelinePresentation` computes every row's height and position once per data or filter change, from the fixed sizes in `TimelineRowGeometry`. The scroll view therefore has its final height at once, and rows can be mounted only near the viewport.

`TimelineVirtualDocumentView` is a plain AppKit document view. It hosts one SwiftUI row per `NSHostingView` and mounts rows within 240 pt of the viewport. Built rows stay with their pull request, up to 60, so scrolling back over them shows them at once; the farthest are evicted first. New rows are built after the visible ones within 6 ms per frame, and a content change rebuilds a retained row only when it comes back near the viewport. Until a row is ready the document draws a placeholder with the row's title in the same place. The grid, the "Today" rule and the pointer cursor are one `Canvas` behind the scroll view, so pointer movement never invalidates rows. All pointer behaviour on the timeline lives in `TimelineInteraction` and the `timelinePointer` modifier, applied to the axis and to every row: on the track column the pointer shows its date, a drag selects a range of quiet time, and a click clears it. Rows select on tap rather than as buttons, so a drag can start on any row; header and stack toggles cover only the label column. A click below the last row reaches the document view, which clears the range the same way.

The engine is custom on purpose. In October 2026 an `NSTableView` with SwiftUI cells was measured against it on the same 68 pull requests, scrolling 600 frames: the table dropped 19–28 frames over 16.7 ms at 12 and 40 pt per frame, in Debug and Release; this engine dropped 0–1. The table lays out each newly visible SwiftUI row synchronously in the frame it appears, which costs 15–25 ms for a full row. Preparing rows ahead of the viewport on later frames is what keeps scrolling smooth. Revisit if SwiftUI hosting becomes cheaper.

## Data certainty

CI detail lists are bounded. The overall status comes from GitHub's `statusCheckRollup.state`, including Actions detail mode. A legacy cache can expose a known failure or pending check, but a successful detail slice cannot establish overall success.

If GitHub says older timeline events were omitted and the relevant activity/review request is absent, quiet time is unknown. The UI uses neutral styling and age-based search/actions/notifications omit that unknown value. The layout keeps a fallback position based on `updatedAt`; it is not a claimed exact quiet age. Old snapshots without history truncation metadata retain their previous fallback behavior.

## Verification

Focused Swift Testing files cover the HTTP transport/client, cache/progressive refresh, projections/policies, search, rendering and native scrolling. Shared fixture infrastructure lives in `TestSupport.swift`. The hosted app starts with a fresh preferences suite, no selected production account, no automatic refresh or notification authorization, and an isolated temporary cache.

Rendered stack fixtures check 2, 3 and 10 layers against the same placement contract. Native-scroll regressions check synchronous tab replacement, bounded hosting, offscreen selection and 68-PR programmatic scrolling. These tests measure layout work, not trackpad FPS. A large expanded stack is still one virtual block; subdividing it would require a separate change to preserve stack rail and dependency rendering.

For measured CPU costs and an opt-in replay of cached data, see [autonomous scroll profiling](scroll-profile-2026-10-05.md).
