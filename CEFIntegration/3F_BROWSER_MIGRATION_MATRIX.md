# 3F Browser standalone-engine migration acceptance matrix

The requested end state is for 3F Browser itself to be a full, standalone browser that owns ordinary navigation and Google OAuth. A separate CEF window, CEF Views shell, WKWebView, or browser engine embedded under developer control is not the final architecture. Google sign-in must run in 3F's normal browser tab, with user-visible destination and connection details. Keep the current installed browser and profile intact until the new 3F candidate passes the complete feature and runtime gates below. Source presence, a rendered sign-in page, or unit tests alone do not prove Google acceptance.

## Browser structure and Google sign-in

| Requirement | Existing implementation/evidence | Replacement acceptance |
|---|---|---|
| 3F is the browser, not an embedded view | Installed product is SwiftUI + WKWebView; CEF experiments use the embeddable CEF framework and are separate candidates. | Ship 3F as a complete standalone browser application based on a full browser distribution/runtime. It owns its browser process, navigation UI, tabs, profile, and OAuth page; do not use CEF or WKWebView as the OAuth user agent. |
| User can inspect destination and connection | Current 3F has an address/search field. An upstream CEF probe exposed an address field and site-information control, but is not product proof. | In 3F's normal browser chrome, show the exact requested/current URI, secure connection state, and certificate/site details through the complete OAuth redirect chain. |
| Google OAuth acceptance | Google policy prohibits directing OAuth to a developer-controlled embedded user agent. Neither an OAuth handoff nor a CEF sign-in screenshot proves acceptance. | Test a real 3F-owned browser tab and callback without user-agent spoofing, cookie copying, or opening a separate embedded login window. Record the exact Google result; do not claim Google approval from source or UI appearance alone. |
| Address/search and ordinary web navigation | `BrowserModel.submit`, `SearchProvider`, URL guard, external URL router, and navigation feedback. | URL entry, search, redirects, reload, popup and external-link routing all stay in the 3F browser and respect Focus Fence policy. Google OAuth is not a special sidecar route. |

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
| Focus Fence policy is applied by the browser | `ThreeFBrowserControl.swift`, `FocusFenceConnectionService.swift`, `FocusFenceSearchResultFilter.swift`; `ThreeFBrowserControlTests`, `FocusFenceSearchResultFilterTests` | Admin-managed Focus Fence policy is delivered as the browser's managed policy plugin/extension. The browser reports the applied policy revision and fails closed for restricted navigation when policy is unavailable. |
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

## Standalone 3F browser release gate

1. Keep the installed 3F build, profile, and rollback copy until the standalone 3F candidate passes the full feature matrix.
2. The primary 3F app must own a full browser engine and its normal navigation surface; a CEF or WKWebView OAuth sidecar is not an acceptable endpoint.
3. Integrate the Focus Fence administrator plugin, Only Chat control, AI Mod side panel/conversation list, existing diagnostics, tabs/sessions, downloads/uploads, reader, bookmarks, history, and media behavior.
4. Verify normal URL navigation and the full Google sign-in/callback journey in 3F's own browser tab, including visible URI and TLS/certificate details. Do not spoof browser identity or copy cookies between engines.
5. Preserve a reversible profile/data migration and verify restart, Focus Fence fail-closed behavior, and rollback before installation or replacement.

## Full-engine parity gate

The feature-parity rows are requirements for this requested migration, not optional future work. Source presence and unit tests alone do not establish runtime parity.

## Current status — 2026-11-12

- Installed 3F is still build20 using SwiftUI + WKWebView.
- The upstream CEF sample displayed Google sign-in controls, but CEF is an embedded framework and that probe did not prove policy acceptance or successful authentication.
- The auth-only CEF candidate passes local signature checks but exits before a persistent window. The latest `NSWorkspace` launch callback succeeded while the process still exited before UI; no Google login was attempted.
- The installed 3F build20 remains SwiftUI + WKWebView and unchanged. A standalone full-browser product, Focus Fence plugin, Only Chat/AI Mod, feature parity, diagnostic durability, OAuth journey, install, and rollback proof remain outstanding.
