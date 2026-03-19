# PR Harbor

GitHub pull requests in your menu bar.

A native macOS menu bar app that keeps you on top of your code reviews, assignments, and PRs — without leaving your workflow.

## Features

- **Three PR tabs** — Review Requested, Assigned, My PRs
- **CI status** — GitHub Actions and status checks with colored dots
- **Badges** — Draft, Stale, Merge Conflict, Changes Requested
- **Features** — Group related PRs across repos into named collections
- **Auto-detect** — PRs with matching branch names across repos are grouped automatically
- **Search** — Filter PRs by title, repo, author, number, or branch
- **Sort & Group** — Sort by date, group by repository with collapsible headers
- **Notifications** — Desktop alerts for new PRs with "Open PR" action button
- **Stale detection** — Configurable threshold to flag inactive PRs
- **Quick actions** — Copy branch name, copy URL, open in browser
- **Onboarding** — GitHub OAuth device flow or Personal Access Token
- **GitHub Enterprise** — Custom API URL support
- **Light & Dark mode** — Adaptive theme

## Install

### Homebrew

```sh
brew tap nezdemkovski/tap
brew install prharbor
```

### Download

Grab the latest `.dmg` from [GitHub Releases](https://github.com/nezdemkovski/prharbor/releases).

> **First launch:** macOS may show a security warning. Run `xattr -cr /Applications/PRHarbor.app` or right-click → Open → Open.

## Setup

1. Open PR Harbor from the menu bar
2. Click **Sign in with GitHub** (OAuth) or paste a [Personal Access Token](https://github.com/settings/tokens/new?scopes=repo) with `repo` scope
3. Done

## Author

Made by [Yuri Nezdemkovski](https://nezdemkovski.com)

## License

[MIT](LICENSE)
