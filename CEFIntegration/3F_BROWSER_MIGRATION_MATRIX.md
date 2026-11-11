# 3F Browser auth-sidecar acceptance and future migration matrix

The user's current direction keeps the existing SwiftUI + WKWebView 3F Browser as the normal browser and uses CEF only for a restricted Google-auth transaction. The sidecar does not replace or inherit 3F's normal browser functions, so it does not need full feature parity. The remaining migration rows are a gate only if a future change proposes replacing the main browser engine. “In source” is not the same as installed/runtime proof.

## Browser structure and Google sign-in

| Requirement | Existing implementation/evidence | Replacement acceptance |
|---|---|---|
| Existing 3F browser stays primary | Installed product is SwiftUI + WKWebView. The CEF auth window is a separate helper and must not replace normal 3F tabs or the default handler. | Normal navigation and existing functions remain in 3F; CEF launches only for Google auth and cannot browse arbitrary sites. |
| User can inspect destination and connection | WKWebView product has an address/search field; upstream CEF probe exposed an address field and “View site information” control while showing Google Accounts. | Show the exact current host, secure-connection status, and certificate/connection details in the 3F browser chrome; retain them during OAuth redirects. |
| Google OAuth acceptance | Google policy rejects developer-controlled embedded user-agents. A CEF sample displaying the sign-in page is not acceptance evidence; actual policy acceptance remains unknown. | Treat CEF as an auth-only experiment until a real sign-in and callback complete. Do not spoof the user agent or copy cookies to WebKit. |
| Auth sidecar scope and return | The CEF policy allows the exact originating HTTPS site plus Google auth/consent endpoints; CEF uses its own profile. The source is rechecked through Focus Fence before launch. | Address entry, redirects, links, and popups outside that origin and the auth endpoints are blocked. Callback cookies remain in Chromium and are not shared with WebKit. |
| Address/search and ordinary web navigation | `BrowserModel.submit`, `SearchProvider`, URL guard, external URL router, navigation feedback. | Enter URL/search, redirects, reload, and external HTTP/HTTPS links route to the expected 3F tab and respect Focus Fence policy. |

## Existing user-facing feature parity

| Feature | Current source locations / focused coverage | Replacement acceptance |
|---|---|---|
| Back, forward, reload, keyboard commands | `BrowserView.swift`, `BrowserWebView.swift`; `BrowserKeyboardCommandsTests`, `BrowserNavigationFeedbackTests` | Visible controls, keyboard shortcuts, loading/error feedback, and page state match the current product. |
| Tabs, background tabs, context menu, multiple windows | `BrowserView.swift`, `BrowserContextMenu.swift`; `BrowserTabSelectionPolicyTests`, `BrowserContextMenuTests`, `BrowserPopupRoutingTests` | Open/select/close tabs, background tabs, open in new window, context-menu actions, and window-to-tab routing all work. |
| Session restore and per-window isolation | `BrowserSessionStore.swift`, `BrowserView.swift`; `BrowserSessionStoreTests` | Normal quit/relaunch restores each window/tab and the AI Mod session independently; no tab/profile cross-contamination. |
| Bookmarks and quick links | `BrowserModel.swift`, `BrowserSettingsView.swift`, `BookmarkHTML.swift`; `BookmarkHTMLTests` | Add/remove, import/export, deduplication, quick-link navigation, and persistence survive profile migration. |
| Installed web apps | `BrowserModel.swift`, `BrowserView.swift`; `InstalledWebAppTests` | Install/open/remove a website as its own 3F window and preserve its destination/title. |
| Downloads | `BrowserWebView.swift` WKDownload delegates | Download known file types, choose destination, show completion/failure, and reject downloads in restricted/embedded modes as before. |
| File and photo upload | `BrowserWebView.swift` open-panel delegate; `BrowserFileUploadTests` | File and photo selection completes from a visible 3F page; cancel and directory-selection behavior remain correct. |
| Reader mode | `BrowserView.swift`, `ReaderArticle.swift`, `ReaderModeView.swift` | Extract a normal article, render the reader view, and present a clear failure state for unsupported pages. |
| Browser history | `BrowserModel.swift`, `ThreeFBrowserControl.swift` history endpoint | History records/clears persist; Only Chat read/back/forward actions target the correct live 3F window and return confirmed state. |
| Theme and hot theme module | `BrowserModel.swift`, `HotModuleStore.swift`; `BrowserThemeTests`, `HotModuleStoreActivationTests` | Theme import/validation/activation/rollback and reload behavior remain available without replacing the browser engine at runtime. |
| Media-site prompt and snooze | `MediaSiteCandidate.swift`, `MediaSiteSnoozeStore.swift`; `MediaSiteCandidateTests`, `MediaSiteSnoozeStoreTests` | Prompt only for eligible sites; ignore/confirm/defer and 24-hour snooze persist across normal relaunch. |
| Browser settings and website data | `BrowserSettingsView.swift` | Search provider, bookmarks, engine/support status, diagnostics, and clear-data controls work; migration does not silently erase profile data. |

## Focus Fence administrator policy plugin

| Requirement | Current implementation/evidence | Replacement acceptance |
|---|---|---|
| Focus Fence policy is applied by the browser | `ThreeFBrowserControl.swift`, `FocusFenceConnectionService.swift`, `FocusFenceSearchResultFilter.swift`; `ThreeFBrowserControlTests`, `FocusFenceSearchResultFilterTests` | Admin-managed Focus Fence policy is installed/enabled as a browser policy extension/plugin. The browser reports the policy revision and fails closed for restricted navigation when policy is unavailable. |
| Domain, URL-part, keyword, exception, schedule rules | `ThreeFBrowserControl.focusFenceAllows` and the search-result filter | Verify allow, deny, exception, redirects, popup, subframe/resource boundaries, schedule refresh, offline failure, and policy update behavior through the real plugin. |
| Google sign-in remains usable under policy | Current Focus Fence authorization path checks destinations; CEF restricted policy is only a probe. | Auth and consent endpoints are handled by the browser directly; admin policy does not spoof the user agent or rewrite OAuth URLs. Explicit Focus Fence denials remain visible and auditable. |
| YouTube navigation and playback quota | `YouTubeUsageReporter.swift`, `YouTubePreviewPlaybackBlocker.swift`, `ThreeFBrowserControl.swift`, `BrowserModel.swift`; YouTube policy/summary tests | Page access, visible/hidden playback accounting, hourly/daily stop, unavailable-budget behavior, Focus Fence read-after-write, and user-visible status all pass in the replacement. |
| Extension compatibility | `ExtensionCompatibility.swift` currently reports WebKit and Chrome extension unsupported. CEF extension probe only verified loading, not rule behavior. | Test the actual Focus Fence extension/plugin package and each required permission/action. Do not claim generic Chrome/Firefox extension compatibility from one successful load. |

## Only Chat, AI Mod, diagnostics, and migration safety

| Requirement | Current implementation/evidence | Replacement acceptance |
|---|---|---|
| Only Chat control and AI Mod window | `ThreeFBrowserControl.swift`, `BrowserView.swift`, `AIModeNavigationPolicy.swift`, `BrowserSessionStore.swift` | Browser-control API reads/navigates/history-manages only the intended tab/window; AI Mod shows its side panel/conversation list and restores its own tabs. |
| Privacy-minimal local diagnostics | `GoogleOAuthHandoffDiagnostics.swift` writes `~/Library/Application Support/3F Browser/diagnostics.jsonl`; media MIME/extension is filtered. | Verify durable append/read/rotation/clear on the installed candidate for popup storms, blocked/failed navigation, Google handoff/outcome, unsupported media. Never persist URLs, query strings, page text, account identifiers, cookies, or tokens. |
| Profile and secret migration | Current WKWebsiteDataStore and `BrowserSessionStore` are separate from CEF profiles. | Make a reversible, documented migration of bookmarks/history/tabs/settings only; preserve existing WebKit profile, session cookies, downloads, and rollback copy until user-visible candidate proof passes. Never copy cookies into another engine. |
| Clean restart and recovery | Existing installed build20 and rollback copies are retained. | Candidate quits normally, reopens with the migrated data, keeps the Google/Focus Fence boundary, and can roll back without corrupting the current profile. |

## Auth-sidecar release gate

1. Keep the installed 3F app and all existing functions on the current WebKit engine.
2. Build/sign the CEF sidecar with matching upstream CEF app/helper IDs and require the explicit `--3f-auth-only` switch.
3. Verify the Google auth page, exact-origin callback path, and denial of arbitrary address-bar, redirect, and popup destinations.
4. Verify the Focus Fence decision and diagnostics at the 3F handoff boundary. Google acceptance and session continuity remain unproven until the real login journey succeeds.
5. Never set the sidecar as default or replace the existing 3F browser as part of this auth-only change.

## Future full-engine migration gate

The feature-parity rows above still apply if the user later asks to replace the main browser engine. Source presence and unit tests alone do not establish runtime parity.

## Current status — 2026-11-12

- Installed 3F is still build20 using SwiftUI + WKWebView.
- The identity-preserving upstream CEF sample displayed Google sign-in controls, but this did not prove Google policy acceptance or successful authentication.
- CEF's custom 3F identity candidate still exits before creating a browser window. CEF/Chromium product integration, all feature rows, Focus Fence plugin execution, Only Chat/AI Mod, diagnostic durability, Google login, and install remain unverified.
- No replacement candidate is authorized by this matrix; it is a guard against losing current 3F functionality during the user-authorized migration.
