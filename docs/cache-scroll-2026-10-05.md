# Startup cache and scrolling — 2026-10-05

The store previously started empty and waited for all three paginated GitHub queries. Each query includes PR history and checks. There was no persistent PR cache. The popup also tracked the hosting controller's ideal size, and LazyVStack created complex rows as they entered the viewport.

## Cache and refresh behavior

- A bounded JSON snapshot lives in the app's own Caches directory, `PRHarbor/Pulls/snapshot-v1.json`. Encoding, decoding and disk access run on a separate actor. Writes are atomic; directory permissions are 0700 and file permissions 0600. No authentication credentials are cached.
- The snapshot identifies the selected CLI username, API URL, check mode, draft policy and fetched categories. A different account, host or query configuration cannot restore it. Unsupported/corrupt/future-dated snapshots are ignored. Retention is seven days; the size limit is 8 MiB.
- Startup restores saved rows before contacting GitHub. A complete snapshot younger than the configured refresh interval skips another immediate full fetch. An older or incomplete snapshot stays visible while revalidation runs. Opening the panel also checks whether an update is due; manual Refresh always requests live data.
- During the first uncached load, ready categories appear and are persisted without waiting for the slowest query. These snapshots are marked incomplete and always revalidated. `Cached · partial` distinguishes an incomplete restored list. A fully successful refresh replaces it with a complete snapshot.
- A failed background refresh keeps the previous rows and their real timestamp. Restoration does not send PR notifications or reconcile snoozes against old history. An account mismatch clears the displayed data.
- Writes and removals are ordered, so signing out/clearing during a pending save cannot resurrect an old snapshot. Generation checks discard results from cancelled requests and earlier CLI connections. Repeated requests are coalesced; equal PR arrays are not republished. Refresh scheduling starts from completion, avoiding a freshness check that accidentally skips the next interval after a slow request.

Production still obtains fresh required categories through `gh api`, including their current history and CI state. This change does not implement per-PR API deltas or replace API reads with scraped CLI output. CLI authentication and organization permissions are unchanged.

## Scrolling

The popup and its hosted document have explicit sizing; automatic ideal-size tracking is disabled. Popup dimensions follow the SwiftUI panel's bounds only when those bounds change. Timeline rows use their known 474-point track width rather than a GeometryReader for every track. Track graphics and liquid stack rails render asynchronously. Cursor-guide updates pause during scrolling.

For up to 120 visible navigable PRs, `TimelineNativeScrollView` keeps the existing SwiftUI rows in a stable AppKit NSScrollView document. Scrolling moves the clip bounds while preserving row lifetimes. Larger collections retain the lazy SwiftUI path to limit initial view creation and memory. Row ranges cover 50-point PRs, 44-point stack layers and collapsed groups; keyboard navigation scrolls the selected layer into view. Document updates retain the top visible group and its offset. Keyboard handlers are shared between the outer panel and its independently hosted document. The document inherits the panel's light/dark appearance.

SwiftUI row components, tooltips, context menus, selection, repository collapse, timeline brushing and the existing header/detail design remain in place. Light and dark snapshots were visually inspected.

## Validation and limits

The native scrolling test uses 68 fixture PRs, three full down/up traversals (90 clip-bound updates), actual NSScrollViews and NSHostingViews. It checks that the document scrolls, the viewport size stays fixed and scrolling does not report new panel sizes. Test windows explicitly remain owned by Swift until teardown.

The comparison run with Swift `-O` reported:

| Container | Median layout | p95 layout | Maximum layout |
| --- | ---: | ---: | ---: |
| SwiftUI lazy | 8.24 ms | 16.61 ms | 35.83 ms |
| SwiftUI eager | 9.31 ms | 18.36 ms | 21.11 ms |
| AppKit document | 5.11 ms | 11.62 ms | 12.90 ms |

The final ordinary Debug run reported 5.30 / 9.28 / 12.40 ms for the AppKit document. These are synchronous layout timings, not GPU frame times or a trackpad FPS measurement. Runs have normal scheduling variance; the figures do not establish a universal speedup. Live scrolling on the user's own PRs and a timed production warm restart have not been independently confirmed: diagnostic launches ended before their GitHub load completed.

Tests also cover persistent restoration, account/host/query isolation, retention and corrupt data, freshness deadlines, stale-while-revalidate, partial-result persistence, late category results, save/clear ordering and stack-layer scroll ranges. The existing CLI transport, search, intelligence policy, notification-tracker and rendering tests are retained.

API references: [NSHostingController sizing](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions), [asynchronous Canvas drawing](https://developer.apple.com/documentation/swiftui/canvas/init(opaque:colormode:rendersasynchronously:renderer:)), [NSScrollView](https://developer.apple.com/documentation/appkit/nsscrollview).

Final validation: 76 tests in 14 suites passed (`/tmp/prharbor-cache-final-test.log`); Debug and Release build logs are `/tmp/prharbor-cache-xcode-debug-build.log` and `/tmp/prharbor-cache-release-build.log`. The check-mode setting retains its original raw Defaults representation despite Codable support for snapshots.

Both final builds succeeded. Release is updated at `build/StatusMenu/PRHarbor.app`; the existing Xcode DerivedData Debug app is also updated. Both have an ad-hoc signature with the project's App Sandbox and network-client entitlements preserved and pass strict signature verification. Temporary diagnostic app copies were removed.
