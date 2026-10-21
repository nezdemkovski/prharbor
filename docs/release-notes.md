PR Harbor now connects with a personal access token and no longer needs GitHub CLI.

- **Personal access token.** Settings → Account opens GitHub's new-token form with the `repo` and `read:org` scopes preselected; paste the token and choose Connect. One classic token covers all your organizations without approving an OAuth or GitHub App in each of them. The token is kept in your login Keychain and sent only to the configured GitHub host.
- **Faster refresh.** A refresh first lists your pull requests with their change markers, then fetches full details only for new or changed ones, in parallel. A typical refresh takes about 3 seconds instead of about 14.
- **App Sandbox.** PR Harbor runs sandboxed again, with only outgoing network access.
- **Sturdier sync.** Every field GitHub may return as null, such as a check run without a details link, is handled instead of failing the whole page. GitHub errors are recognized by their codes. Rejected tokens and rate limits are reported with the step to fix them or the time to retry.
- **Panel.** The panel sizes itself to its content, and the menu bar count and the timeline share one up-to-date view of your pull requests.

**Updating from 0.2:** settings start from their defaults once, because sandboxed preferences live in the app's container. Add a personal access token in Settings → Account and re-apply your preferences.

**Requirements:** macOS 26 or later on Apple silicon, and a GitHub personal access token with the `repo` and `read:org` scopes. For organizations with SAML single sign-on, authorize the token for them on GitHub.

**Signing:** the DMG contains an ad hoc signed, sandboxed app with Hardened Runtime. This personal build has no Developer ID signature or Apple notarization; macOS can require manual approval under Privacy & Security when opening a downloaded copy, and can ask once for Keychain access after an update.

`SHA256SUMS` is provided for download integrity verification.
