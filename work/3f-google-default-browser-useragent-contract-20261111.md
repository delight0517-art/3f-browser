# 3F Google-compatible browser-engine migration contract

## Goal and scope

- User-visible result: 3F opens its bundled Chromium window for the originating site and Google sign-in. That window must prevent navigation elsewhere, including YouTube and Google Search.
- Feature/module ID and affected files: `google-auth-restricted-cef-host`; `GoogleOAuthNavigationPolicy`, `GoogleOAuthHandoffDiagnostics`, `CEFBrowserRuntime`, CEF policy patch/build/package scripts, and this contract.
- Callers, shared resources and dependencies: Chromium Embedded Framework (CEF) 156 arm64 `cefclient` host; 3F passes the source origin and an isolated profile. The main SwiftUI browser UI still uses WKWebView; the Chromium host is a separate bundled app window.
- Mac/Windows adaptations: Mac implementation only; no Windows source or receiver change requested.

## Change and safety

- UI, design-token and font changes: None; reuse the existing default-browser setting and status.
- State to preserve: Existing browser profiles, cookies, tabs, Only Chat AI Mod sessions, Focus Fence state and diagnostics. Never log OAuth query, fragment, code, token, account or page contents.
- In-flight work that must finish before applying: Preserve the existing 3F window and profile; install only after the signed candidate is ready and rollback retention is reconciled.
- Apply route: 3F launches the bundled CEF host at its originating page. CEF permits page navigation only to the exact source origin, `accounts.google.com`, and `consent.google.com`; it blocks other destinations, YouTube/media hosts, and Google Search on navigations, redirects, popups, and address-bar requests. Third-party resources can still load for the allowed pages.
- Rollback path and known limits: Restore the retained previous signed bundle. The existing CEF probe proves rendering and isolated profiles only. CEF is not automatically Google-approved; a full browser-shaped UI or changed User-Agent alone does not prove compliance. Google's policy calls for a system browser and rejects embedded user-agents, so product architecture and Google's real sign-in result are required evidence.

## Proof

- Focused check and expected result: Compile the Swift product and patched CEF host, verify signatures, and inspect the exact local navigation policy. Do not run tests unless requested.
- Source revision and changed-path list: Record the exact commit and owned source paths after the scoped commit.
- Runtime proof: Build and signature checks passed for the local candidate. Installation, address-bar behavior, real Google sign-in, installed profile isolation, and Google policy acceptance remain unverified.
- Windows state: Not requested / not changed.
- Remaining blocker and next action: Install/runtime verification remains pending. The CEF window is a separate bundled process, and the main 3F UI still uses WKWebView. Google acceptance remains unverified until an actual sign-in succeeds; the source-site-only navigation policy may also need adjustments if Google's auth flow requires additional top-level destinations.
