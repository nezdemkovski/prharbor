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

## Responsibilities

- `AppDelegate` owns menu bar and settings window lifetime. `StatusBarController` owns the status item and popover. `AppRuntime` prevents hosted tests from starting production services; `AppPreferences` supplies either the existing preference domain or a fresh test suite.
- `GitHubSession` owns the connected account, its Keychain-stored personal access token and the connection generation. `GitHubHTTPTransport` is the transport boundary: authorized HTTPS requests to the REST `user` endpoint and GraphQL, with token, rate-limit and HTTP failures mapped to `GitHubAccessError`. `GitHubClient` builds and decodes GitHub requests, carries the connected login and verifies it against `viewer` in each search. `GitHubTokenConnector` validates a pasted token and its classic scopes before it is stored.
- `PullRequestStore` owns refresh cancellation/generations, progressive category results, persistent cache ordering, timers and side effects. Stack mutation uses its injected client provider and forces revalidation after any mutation attempt that could have completed layers. Account/scope changes invalidate old work.
- `TimelineInput` projects category data into deduplicated `TimelineItem` values, preserving review-request membership even when another category supplies the visible item. Store counters, settings samples and the screen use this projection.
- `TimelineNotificationPolicy` and `TimelineSnoozePolicy` make pure decisions. The store applies their results and performs notifications/preferences writes.
- `TimelineScreenController` owns tab, filter, selection, collapse and asynchronous search interpretation. It publishes one immutable snapshot containing the matching presentation, selected item, brief, brush and search state. Keyboard selection reuses the cached presentation. Focus, hover, pointer gestures and scrolling stay in the view.
- `TimelinePresentation` groups and orders rows and supplies navigation/ranges. `TimelineRowGeometry` defines the sizing contract used by both presentation and rendered rows. `TimelineNativeScrollView` mounts the visible/prefetch host set with incremental scroll preparation; tab replacement prepares visible rows synchronously.

## Data certainty

CI detail lists are bounded. The overall status comes from GitHub's `statusCheckRollup.state`, including Actions detail mode. A legacy cache can expose a known failure or pending check, but a successful detail slice cannot establish overall success.

If GitHub says older timeline events were omitted and the relevant activity/review request is absent, quiet time is unknown. The UI uses neutral styling and age-based search/actions/notifications omit that unknown value. The layout keeps a fallback position based on `updatedAt`; it is not a claimed exact quiet age. Old snapshots without history truncation metadata retain their previous fallback behavior.

## Verification

Focused Swift Testing files cover the HTTP transport/client, cache/progressive refresh, projections/policies, search, rendering and native scrolling. Shared fixture infrastructure lives in `TestSupport.swift`. The hosted app starts with a fresh preferences suite, no selected production account, no automatic refresh or notification authorization, and an isolated temporary cache.

Rendered stack fixtures check 2, 3 and 10 layers against the same placement contract. Native-scroll regressions check synchronous tab replacement, bounded hosting, offscreen selection and 68-PR programmatic scrolling. These tests measure layout work, not trackpad FPS. A large expanded stack is still one virtual block; subdividing it would require a separate change to preserve stack rail and dependency rendering.

For measured CPU costs and an opt-in replay of cached data, see [autonomous scroll profiling](scroll-profile-2026-10-05.md).
