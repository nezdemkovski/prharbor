# Native app cleanup

Approved by the user on 2026-10-05. Baseline: b60fa39 plus the existing, uncommitted CLI-only, cache and virtual-scroll implementation. Preserve those changes. No commit, push, GitHub authentication or organization requests.

## Scope and order

1. Isolate the hosted Swift Testing launch from production account checks, notification authorization, preferences, migrations and persistent cache. Split the existing suites into focused files; retain shared test support.
2. Separate bounded CI details from authoritative aggregate status. Fetch overall rollup state even in Actions mode. Incomplete detail slices must not produce a false green summary. Truncated history must carry uncertainty when the needed event is absent and must not produce exact-age actions or stale notifications.
3. Revalidate after successful or partially successful stack mutations, including when a refresh is already running. Respect the injected session/client provider and account scope; do not hide the original error.
4. Remove unreachable PRListView/PRRowView/legacy stack and detail UI after extracting live AsyncAvatarView, SectionTitle and OnboardingView. Preserve shared domain/grouping helpers and move the obsolete row equality regression to the live boundary. Remove default keys only after checking every reference.
5. Introduce a timeline screen controller with an immutable derived snapshot, updated together from data and filter inputs. Keep focus and pointer gestures in the View. Preserve literal/natural search, selection, stack companions, collapse, keyboard, scale and preview behavior.
6. Centralize row/stack geometry, including large collapsed stacks. Normalize selection per row so unaffected rows remain equal. Retain AppKit virtualization, bounded hosts, incremental scroll preparation and synchronous tab replacement.
7. Extract pure notification/snooze policies and a shared timeline item projection from the store. Keep cache write/removal sequencing, freshness, cancellation and account generation guards. Avoid introducing layers without a concrete responsibility.

## Verification

Use Swift 6 main-actor UI objects and nonisolated Sendable value models. Add meaningful regressions for aggregate CI vs truncated details, truncated review history, partial rebase and rebase during refresh, large collapsed stacks, same-layout tab changes, isolated test startup and notification/snooze policies.

```
xcodebuild -project PRHarbor.xcodeproj -scheme PRHarbor -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/pullbar-derived -clonedSourcePackagesDirPath /Users/yuri/Library/Developer/Xcode/DerivedData/PRHarbor-fpxzpkowwumourhcozokttwdrkes/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO test
```

Expected: all tests pass, no Swift concurrency errors or view-update publication warnings. Build Debug and Release with the same destination and package directory. Validate light/dark snapshots and tab/keyboard/scroll geometry. Programmatic layout timings are not physical scroll FPS. Update build/StatusMenu/PRHarbor.app, sign with the existing PRHarbor.entitlements, verify signature and restart only this app.

## Boundaries

Do not change the prototype, auth permissions, CLI bridge behavior, GitHub mutation protocol, design/spacing for ordinary rows, or user data. Shared Xcode references and test support are integrated centrally. If uncertainty cannot be resolved from the bounded API response, display it honestly rather than inventing an exact age or success state.

## Status

Completed on 2026-10-05.

- Removed the unreachable legacy list/detail tree and unused display defaults after extracting the three live shared components. The row-change regression now checks the active rendered equality boundary.
- Added isolated test startup/preferences/cache and split the original test monolith by responsibility.
- Implemented overall CI state, unknown quiet periods for explicit history truncation, injected mutation revalidation, shared projection and pure policies.
- Replaced duplicated panel/search state with one screen snapshot/controller; selection reuses presentation and affects only matching rows. Removed the obsolete search controller and summary callback.
- Shared geometry now matches rendered collapsed stacks at 2, 3 and 10 layers (70/72/114 points). The two-layer rendered fitting regression caught an SF Symbol minimum-height mismatch; the shared body frame corrected it.
- Final hosted test run: **99 tests / 18 suites passed**, 17.062 seconds, `/tmp/prharbor-cleanup-test.log`, result `/tmp/pullbar-derived/Logs/Test/Test-PRHarbor-2026.10.05_02-37-22-+0200.xcresult`.
- Native scroll fixture: 68 PRs / 90 viewport updates, median 1.007 ms, p95 10.154 ms, max 12.493 ms. Existing bounded-host, immediate tab replacement and offscreen keyboard selection checks passed. These are layout measurements, not trackpad FPS.
- Light/dark panel snapshots inspected. Settings/empty/error snapshot tests passed. No Swift compiler concurrency or view-update publication warnings; Xcode emitted its usual no-AppIntents metadata warning and the test host logged system autoShortcut service connection messages.
- Debug and Release builds passed (`/tmp/prharbor-cleanup-debug-build.log`, `/tmp/prharbor-cleanup-release-build.log`). Replaced `build/StatusMenu/PRHarbor.app` with Release; both canonical Release and standard Debug bundles signed and strictly verified with the existing sandbox/network entitlements.
- Restarted canonical app; running process verified as PID 9596. CUA cannot attach to its closed menu popover (timeout), so physical scrolling and live-panel visual acceptance are not claimed. No authentication, organization access request, GitHub mutation, commit or push was performed during this cleanup.

Remaining explicit limits: bounded GitHub detail/history slices; old snapshots without truncation metadata keep their previous fallback; large expanded stacks remain a single virtual block. Component boundaries and verification expectations are documented in `docs/architecture.md`.
