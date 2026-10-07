PR Harbor now centers on a native pull-request timeline with All, Mine and Reviewing tabs, repository groups, quiet-time filters, event history and stack details.

- GitHub uses your existing `gh` login through direct background `gh api` requests. Built-in OAuth, manual tokens and the user-script bridge are removed. PR Harbor does not request organization access or change GitHub CLI permissions.
- A persistent snapshot appears at startup while stale data refreshes. Categories load progressively, and the timeline mounts a bounded viewport.
- Native settings, snooze, CI summaries, keyboard navigation and a right-click Quit menu are included. Natural-language search and morning explanations use optional Apple Intelligence settings, both off by default.
- CI uses GitHub's aggregate check state. Explicitly truncated history is treated as unknown when the relevant activity is missing.

**Requirements:** macOS 27 or later on Apple silicon; GitHub CLI installed and already signed in. After installation, use Settings → Account → Connect GitHub CLI.

**Signing:** the DMG contains an ad hoc signed app with Hardened Runtime. App Sandbox is disabled for direct CLI access. This personal build has no Developer ID signature or Apple notarization; macOS can require manual approval under Privacy & Security when opening a downloaded copy.

**Known limitation:** fast scrolling can still stutter on dense timelines. Profiling isolated repeated SwiftUI row-host layout, and no renderer performance fix is claimed in this release. GitHub event/check detail slices remain bounded.

`SHA256SUMS` is provided for download integrity verification.
