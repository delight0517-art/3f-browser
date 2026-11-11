# 3F Google-compatible browser-engine migration contract

## Goal and scope

- User-visible result: 3F itself is a full browser whose primary web surface and top-level browser UI are owned by CEF Views, with ordinary browser navigation. Google sign-in must use a browser structure instead of the current embedded WKWebView or restricted helper window.
- Feature/module ID and affected files: `threef-primary-cef-browser`; CEF Views build/package integration, browser lifecycle and profile/session migration, `BrowserModel`, `BrowserView`, `ThreeFBrowserApp`, `ThreeFURLRouter`, local diagnostics, Only Chat and AI Mod integration.
- Callers, shared resources and dependencies: Chromium Embedded Framework (CEF) 156 arm64 `cefclient` Views shell with a 3F-only profile. The current SwiftUI/WKWebView app remains installed and available during migration; the preview candidate does not change the system default or installed app.
- Mac/Windows adaptations: Mac implementation only; no Windows source or receiver change requested.

## Change and safety

- UI, design-token and font changes: Replace the browser surface with the CEF Views top-level browser shell while migrating 3F controls and features. Preserve Only Chat/AI Mod, Focus Fence, tab/session behavior, downloads, permissions, URL delivery, and diagnostics.
- State to preserve: Existing browser profiles, cookies, tabs, Only Chat AI Mod sessions, Focus Fence state and diagnostics. Never log OAuth query, fragment, code, token, account or page contents.
- In-flight work that must finish before applying: Preserve the existing 3F app/window/profile and both Nov 8 rollback copies until the replacement build and runtime are verified and the 14-day retention window passes.
- Apply route: Build the CEF Views candidate in full-browser mode with general navigation and an isolated 3F profile. Integrate it as the actual 3F browser surface, migrate the existing features and URL handling, and verify visible browser behavior before considering installation.
- Rollback path and known limits: Keep the signed current 3F app and both Nov 8 rollback bundles. CEF rendering and isolated profiles have only been verified in probes. CEF is not automatically Google-approved; only an actual sign-in result can establish acceptance. Do not claim approval from engine choice or UI structure alone.

## Proof

- Focused check and expected result: Build and sign a standalone full-browser CEF Views candidate with general navigation and a separate profile, then inspect its visible browser shell. Do not run tests unless requested.
- Source revision and changed-path list: Record the exact commit and owned source paths after the scoped commit.
- Runtime proof: The existing separate CEF helper renders web pages, but the full-browser product candidate, integration into the 3F app, real Google sign-in, profile migration, and Google acceptance remain unverified.
- Windows state: Not requested / not changed.
- Remaining blocker and next action: CEF Views is not yet the installed 3F product, and the existing Only Chat/AI Mod, Focus Fence, session, download, permission, URL-routing, and diagnostic behavior has not been migrated. Integrate and verify those surfaces before installation; then run a real sign-in and report Google's result without assuming acceptance.
