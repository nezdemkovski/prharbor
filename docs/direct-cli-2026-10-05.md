# Direct GitHub CLI execution

The macOS script-monitor gear displayed `prharbor-gh` jobs during synchronization. The previous sandboxed transport used `NSUserUnixTask` to run a user-installed bridge for each API request.

GitHub requests now use the existing asynchronous `Process` transport exclusively. The user-script executor, its error case, sandbox detection and repository bridge script are removed. Both Debug and Release disable App Sandbox; Hardened Runtime stays enabled. API request arguments, CLI identity validation, host selection and GraphQL schema fallbacks remain the same. Cancellation and deadlines terminate the owned process, and both output streams are drained concurrently.

Saved bridge paths resolve to the installed `gh` executable without executing the script. The selected account and API host are retained. If gh is missing, the account is preserved and the transport reports the installation error; it can resolve the old path after gh is installed. The existing preference domain and cache format remain in use. A one-time import preserves former sandbox preferences when that file is readable; an unreadable or absent file leaves the current domain intact.

## Verification

- Debug: 100 declared Swift Testing tests in 18 suites passed in 17.987 seconds. The opt-in profiling test was skipped. Coverage includes large stdout/stderr, sanitized child environment, GraphQL errors, cancellation, timeout, bridge path migration, preference migration and account invalidation. `/tmp/prharbor-direct-cli-tests.log`.
- Release build succeeded. `/tmp/prharbor-direct-cli-release.log`.
- The installed Release bundle at `build/StatusMenu/PRHarbor.app` passes strict signature verification. Its entitlements are empty and its signature retains the runtime flag. The local signature is ad hoc.
- The previous running instance was replaced; a single canonical Release instance launched, PID 74158. Its live cache updated at 11:25:07 Europe/Prague with 69 unique PRs: 20 created and 49 requested, complete and matching the saved account. The saved executable is `/opt/homebrew/bin/gh`. No sign-in was needed.
- The live observation started after the initial requests had completed, so it did not capture a gh child. The fresh cache confirms the app's real fetch; source and transport tests establish the direct execution path. The menu-bar gear itself was not visually inspected after replacement.
- The former container preference import did not run in this local launch; existing standard preferences already supplied the selected CLI account. The import path is covered by isolated fixtures.

No organization authorization requests or authentication changes were made. This transport change does not address the separately measured SwiftUI scrolling bottleneck.
