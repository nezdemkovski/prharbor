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
- **Personal access token** for GitHub or GitHub Enterprise, kept in the Keychain

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

1. [Create a classic personal access token](https://github.com/settings/tokens/new?scopes=repo,read:org&description=PR%20Harbor) with the `repo` and `read:org` scopes. For organizations that use SAML single sign-on, choose **Configure SSO** next to the token and authorize it for them.
2. Open PR Harbor from the menu bar and choose **Settings → Account**.
3. Paste the token and choose **Connect**. PR Harbor checks the token's account and scopes, then loads the pull requests it can access.

A personal access token works across all your organizations without installing or approving an OAuth or GitHub App in each of them. PR Harbor stores the token in your login Keychain, sends it only to the configured GitHub API host over HTTPS, and keeps responses out of the shared URL cache. Requests go straight to GitHub's GraphQL API; nothing else needs to be installed. Disconnecting removes the token from the Keychain; revoke it on GitHub if you no longer need it.

Fine-grained tokens also work, but each one covers a single owner, so pull requests from other organizations are missing. GitHub Enterprise is supported through the API URL setting (for example `https://github.example.com/api/v3`); create the token on that host.

Each search response confirms that the token still belongs to the connected account. Rate limits and rejected tokens are reported in the panel with the time to retry or the step to fix them.

### Updating from earlier versions

Version 0.2 connected through GitHub CLI. After updating, add a personal access token in Settings → Account; your other settings are kept. Versions before 0.2.0 were sandboxed and used built-in sign-in, so their settings are not carried over. Their sign-in may remain in Keychain as `com.nezdemkovski.prharbor` items named `githubToken` and `githubSession`; delete them in Keychain Access if you like. PR Harbor never reads them.

## Development

See [architecture](docs/architecture.md) for component responsibilities and data-certainty rules.

- Xcode 27 or newer
- Swift 6.4 compiler in Swift 6 language mode, with Approachable Concurrency and complete concurrency checking
- macOS 26 deployment target

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

Open `PRHarbor/Views/Timeline/TimelinePreview.swift` in Xcode for a SwiftUI preview with sample data. A Debug build launched with `PRHARBOR_PREVIEW=1` presents the sample interface and skips automatic GitHub refresh and notification authorization. Use a separate bundle identifier when launching a standalone preview app to isolate its preferences from the main app.

Ordinary Debug and Release runs both stay in the menu bar, without a Dock icon or a separate timeline window. For an explicit live-data development window, set `PRHARBOR_DEBUG_WINDOW=1` in the Xcode scheme's Run environment. Development windows are not restored on the next launch.

The Test action sets `PRHARBOR_TESTING=1`. Hosted tests skip production startup and notifications, use a fresh preferences suite and temporary cache, and supply fixture GitHub transports. Tests are organized by suite in `PRHarborTests/`; shared transports and gates live in `TestSupport.swift`.

GitHub GraphQL documents are checked against GitHub's public schema, pinned in `Scripts/graphql/github-schema.graphqls`. `Scripts/validate-graphql.sh` (Node.js required) exports every document the client sends, validates it, and rewrites `Scripts/graphql/selected-fields.txt` with each selected field and its nullability; review that diff whenever a query changes, and keep nullable fields optional in the models. The release workflow runs the same check.
