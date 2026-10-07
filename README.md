# PR Harbor

GitHub pull requests in your menu bar.

A native macOS menu bar app that keeps you on top of your code reviews, assignments, and PRs — without leaving your workflow.

## Features

- **PR timeline** — All, Mine, and Reviewing views, grouped by repository
- **Quiet time** — Fresh, aging, stale, and rotting zones with configurable thresholds
- **Event history** — Commits, comments, approvals, and review requests on the timeline
- **Time ranges** — 2 weeks, 1 month, 3 months, and a logarithmic 6-month scale
- **Filters** — Combine terms such as `mine stale`, `noona-api >2w`, a PR number, or a branch; drag across the timeline to filter quiet time
- **Optional Apple Intelligence** — Type plain-language requests directly into the existing search field, or expand a morning brief with up to three PRs and short explanations; independent switches in Settings → Apple Intelligence, both off by default
- **PR stacks** — Connected layers, collapse/expand, target branch, merged layers, and rebase
- **Detail card** — Full title, copy branch, CI logs, history, and the next step
- **Snooze** — Tomorrow, in 3 days, or next week, with optional wake-up on someone else's comment
- **Bot accounts** — Separate group, editable logins and wildcard patterns
- **Native settings** — Separate macOS window with a sidebar and system controls
- **Notifications** — New review requests, assignments, quiet PRs, and an optional morning summary while the app is running
- **Keyboard navigation** — Arrow keys or J/K to select, Return to continue, O to open, S to snooze, / to filter
- **Light and dark mode**, VoiceOver labels, and system typography
- **GitHub CLI**, signed in to GitHub or GitHub Enterprise

Merge, close, review, and reviewer nudges continue on GitHub. Stack rebase uses the GitHub API and asks for confirmation before updating branches. GitHub's latest 60 timeline events are shown; the full history remains available on GitHub.

Apple Intelligence uses Apple's on-device Foundation Models model. Natural-language requests update the current tab after a short typing pause without changing the entered text or opening another window. Existing keyword, repository, PR-number and literal searches stay immediate. Unsupported requests show a short message in the results area. The morning brief selects PRs using status and quiet time, excludes bots, drafts and snoozed PRs, and generates explanations only when expanded. It caches the most recent result until its daily snapshot changes. This is a current overview, not a summary of overnight changes or review discussions. Existing morning notifications remain independent. Model availability depends on the Mac, Apple Intelligence settings, and model readiness; ordinary controls and factual brief entries remain usable when generation is unavailable.

## Install

### Homebrew

```sh
brew tap nezdemkovski/tap
brew install prharbor
```

### Download

Grab the latest `.dmg` from [GitHub Releases](https://github.com/nezdemkovski/prharbor/releases).

> **First launch:** this personal build is ad hoc signed and not notarized. If macOS blocks the downloaded app, open System Settings → Privacy & Security and approve PR Harbor with **Open Anyway**.

## Setup

1. Install [GitHub CLI](https://cli.github.com/) and run `gh auth login` in Terminal if you have not already signed in.
2. Open PR Harbor from the menu bar.
3. Choose **Settings → Account → Connect GitHub CLI**. PR Harbor checks the active account and loads its accessible pull requests.

GitHub CLI is the only connection method. API requests, pagination, stack loading, and user-triggered rebases run through `gh api`; PR Harbor never extracts or copies the CLI token and never runs `gh auth login`, requests organization approval, or changes CLI permissions. Access is limited to what the existing CLI account can already access. If the active account changes, reconnect in Account settings. Disconnecting PR Harbor clears its local account selection and leaves `gh` signed in. GitHub Enterprise is supported through the API URL setting (for example `https://github.example.com/api/v3`).

PR Harbor launches `gh` directly as a background child process. App Sandbox is disabled for this CLI integration; Hardened Runtime remains enabled. No Application Scripts bridge is needed, so synchronization does not create macOS script-monitor menu items. Cancellation and timeouts terminate the owned CLI process. Existing bridge-based account selections migrate to the installed `gh` executable automatically, without another sign-in. The existing preferences domain is retained; preferences from the former sandbox container are imported once if readable.

When updating from a version with built-in sign-in, the app preserves an active CLI connection and retires its old local account selection. A one-time migration deletes only PR Harbor’s two previous credential entries from its own Keychain service. It does not read their contents or touch GitHub CLI credentials. Built-in OAuth and manual token entry are removed.

## Development

See [architecture](docs/architecture.md) for component responsibilities and data-certainty rules.

- Xcode 27 or newer
- Swift 6.4 compiler in Swift 6 language mode, with Approachable Concurrency and complete concurrency checking
- macOS 27 deployment target

Build from the command line:

```sh
xcodebuild -project PRHarbor.xcodeproj -scheme PRHarbor -destination 'platform=macOS' build
```

Run the Swift Testing suite:

```sh
xcodebuild test -project PRHarbor.xcodeproj -scheme PRHarbor -destination 'platform=macOS'
```

## Author

Made by [Yuri Nezdemkovski](https://nezdemkovski.com)

## License

[MIT](LICENSE)

## Interface preview

Open `PRHarbor/Views/Timeline/TimelinePreview.swift` in Xcode for a SwiftUI preview with sample data. A Debug build launched with `PULLBAR_PREVIEW=1` presents the sample interface and skips automatic GitHub refresh and notification authorization. Use a separate bundle identifier when launching a standalone preview app to isolate its preferences from the main app.

Ordinary Debug and Release runs both stay in the menu bar, without a Dock icon or a separate timeline window. For an explicit live-data development window, set `PULLBAR_DEBUG_WINDOW=1` in the Xcode scheme's Run environment. Development windows are not restored on the next launch.

The Test action sets `PRHARBOR_TESTING=1`. Hosted tests skip production startup, notifications and credential migrations, use a fresh preferences suite and temporary cache, and supply fixture GitHub transports. Tests are organized by suite in `PRHarborTests/`; shared transports and gates live in `TestSupport.swift`.
