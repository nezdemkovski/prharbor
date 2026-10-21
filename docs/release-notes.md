PR Harbor 0.4.0 looks at home on macOS 26 and makes the timeline easier to work with.

- **Liquid Glass panel.** The panel sits on the popover's system glass, arrow included. Text and surfaces are tuned to stay readable over it in both light and dark appearance.
- **Native settings.** Settings open in a standard macOS settings window with a sidebar, grouped by purpose, and About uses the standard About window.
- **Timeline selection.** Drag across the timeline from any row to filter by quiet time; the range now ends on any day instead of jumping to fixed stops. Click empty timeline, the axis or the range chip to clear it. Clicking beside a repository or stack header no longer collapses it.
- **Smoother scrolling.** Scrolling back and forth through long lists keeps rows drawn instead of rebuilding them.
- **Steadier panel.** The panel keeps one height while loading, filtering or showing a short list. When nothing matches, it says so and offers Clear Filters.
- **Readability.** Every text color meets WCAG AA contrast against the surface it sits on.

**Requirements:** macOS 26 or later on Apple silicon, and a GitHub personal access token with the `repo` and `read:org` scopes. For organizations with SAML single sign-on, authorize the token for them on GitHub.

**Signing:** the app and the DMG are signed with a Developer ID, notarized by Apple and stapled, so macOS opens them without a Privacy & Security approval. The app runs sandboxed with Hardened Runtime.

`SHA256SUMS` is provided for download integrity verification.
