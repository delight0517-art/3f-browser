# 3F login popup routing — 2026-11-06

- Source change: `BrowserWebView.Coordinator.createWebViewWith` now routes ordinary HTTP(S) `targetFrame == nil` requests to the existing native new-tab callback; existing context-menu new-tab/new-window routing remains unchanged.
- Safety: `ThreeFContextMenuPolicy.safeHTTPURL` rejects non-HTTP(S) and URLs containing user credentials.
- Focused check: `swift test --filter BrowserPopupRoutingTests` — 3 tests passed, 0 failures; incremental debug build completed in 5.61 seconds. Coverage includes opening an HTTPS login target in a tab, refusing named targets, and refusing unsafe URLs.
- Scope limit: Google forbids OAuth authorization inside embedded WKWebView. The popup now appears as a 3F tab, but account sign-in may still be rejected with `disallowed_useragent`. Do not spoof the user agent. Full Google OAuth needs a policy-compliant external/native flow or a supported browser engine; WKWebView does not import external-browser cookies.
- Runtime: no app was launched or installed. SpaceO refused to create an isolated session with `display safety circuit is open: host health: swap_activity`; it also reported that daemon 1.0.9 does not match this MCP server. Trace: `59343823-5c52-421c-9162-ef81f0279a67`. No fallback or retry was attempted.
- Prior changes: unrelated dirty `BrowserView.swift` quick-link install buttons and all existing `work/` artifacts remain outside this slice.
