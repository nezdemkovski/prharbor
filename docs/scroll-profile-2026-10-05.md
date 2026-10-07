# Autonomous scroll profiling — 2026-10-05

## Scope

The user was away from the Mac. Profiling therefore used an isolated optimized test host and a private read-only copy of the local snapshot: **68 unique PRs, 82 presentation rows**. No production preferences, account connection, refresh, notifications or GitHub mutations were used by the replay. The normal app remained running.

The replay traverses the list down/up five times, with 1,200 updates and an 8.333 ms sleep between them. It measures synchronous scroll/layout/display work **and the complete interval between updates**, including deferred SwiftUI preparation. The latter was omitted by the earlier synchronous benchmark. The test window is not a physical trackpad/display recording: these intervals are not FPS or counts of dropped display frames.

## Findings

The normal app's idle sample showed its main thread waiting for events. The replay reproduces UI CPU work even with PRs already loaded and fetching disabled.

Time Profiler captured 9,435 running samples. About **7,172 ms of 9,089 ms of main-thread samples** included NSHostingView work. `NSHostingView.layout()` accounted for 5,887 ms inclusively; `GraphHost.updatePreferences()` for 2,864 ms and `RootGeometry.value` for 1,797 ms. These inclusive times overlap and must not be added. Screen-controller work accounted for 8 ms and avatar work for 38 ms in this recording.

Counters found **zero complete document configurations** during replay and **680 row preparations**. Whole-list/filter recomputation is therefore not the cause in this isolated case. The expensive path is preparation and layout of separate SwiftUI row roots as the viewport advances.

Uninstrumented comparison, using the same snapshot and trajectory:

| Rendering | Median loop interval | p95 loop interval | Median synchronous work | p95 synchronous work | Retained hosts at end |
| --- | ---: | ---: | ---: | ---: | ---: |
| Existing renderer + diagnostic counters | 12.25 ms | 21.57 ms | 1.31 ms | 7.92 ms | 18 |
| Stable row cache, hidden hosts attached | 13.84 ms | 21.53 ms | 2.43 ms | 9.40 ms | 42 |
| Stable row cache, detached hosts, isolated run | 12.99 ms | 25.67 ms | 1.74 ms | 13.55 ms | 42 |

All runs had zero observed unprepared visible rows. The detached cache reduced row rebuilds to 424 but did not reduce latency. Safe-area suppression and moving pointer/brush handlers to the shared scroll area also produced no material improvement. **All rendering experiments were reverted.** The host bound, incremental preparation, synchronous tab replacement, artwork and interaction contracts remain as before.

## Next renderer experiment

Reduce the number of independent SwiftUI hosting roots, instead of retaining more individual row hosts. A single host for a bounded visible/prefetch slice could preserve overlapping rows through stable ForEach identities and avoid rebuilding a separate root graph for each recycled row. This is a proposed experiment, not an implemented or verified fix.

Any such change must retain the existing stack geometry, selection, brush/hover, context menus, immediate tab replacement and bounded mounting. Compare it with this replay before replacing the current renderer; then record physical trackpad behavior when the user is back. This replay does not rule out additional stalls during a live refresh or GPU/display work.

## Repeatable tooling

`NativeScrollingTests.profileCachedPullsWithDeferredRowPreparation()` is opt-in. Ordinary tests skip it and never read the production snapshot. This dense-list replay expects at least 50 PRs. The helper copies an explicitly supplied snapshot into its private output directory, removes that copy when finished, and saves only aggregate JSON and local profiling/test output. Do not commit the private trace or input snapshot.

```sh
xcodebuild -project PRHarbor.xcodeproj -scheme PRHarbor -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/pullbar-profile \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=PRHARBOR_TEST_FIXTURES build-for-testing

python3 Scripts/profile-scroll.py \
  --products /tmp/pullbar-profile/Build/Products \
  --snapshot "$HOME/Library/Caches/PRHarbor/Pulls/snapshot-v1.json" \
  --output /tmp/prharbor-scroll-new-run --trace
```

The fixture flag enables test data in the optimized test host; ordinary production Release excludes it. The output directory must be new. Use a snapshot path the current account can read; sandboxed production caches can require different paths.

Local evidence: `/tmp/prharbor-replay-baseline.trace`, `/tmp/prharbor-replay-baseline-cpu.xml`, `/tmp/prharbor-profile-diagnostics/report.json`, `/tmp/prharbor-profile-row-cache/report.json`, `/tmp/prharbor-profile-detached-cache-isolated/report.json`.

## Final validation

Restored-renderer Debug suite: **100 declared tests / 18 suites passed**, 16.031 s, including the disabled-by-default replay marked skipped. Optimized Release build-for-testing succeeded. The saved helper's `--trace` path was exercised successfully on the restored renderer; final report has 0 configurations, 680 preparations, 18 retained hosts and 0 unprepared visible rows. Its instrumented loop p95 was 23.10 ms and is not used as an uninstrumented before/after comparison.

Logs: `/tmp/prharbor-profile-final-tests.log`, `/tmp/prharbor-profile-final-build.log`, `/tmp/prharbor-profile-final/test.log`, `/tmp/prharbor-profile-final/report.json`, `/tmp/prharbor-profile-final/cpu.trace`. The opt-in fixture condition and lightweight counters support profiling; no renderer optimization was shipped. The running canonical app was not restarted during this investigation.
