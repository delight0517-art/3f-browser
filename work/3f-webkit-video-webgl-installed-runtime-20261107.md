# Installed-runtime QA receipt

- **Date:** 2026-11-07 KST
- **App:** `/Users/rogan/Applications/3F Browser.app`
- **Bundle:** `com.rogan.threef.browser`
- **Version/build:** 0.1.0 (18)

## Observations

- `https://get.webgl.org/` showed “Your browser supports WebGL” and a visible spinning cube.
- `https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4` reached **00:05/00:05** and displayed a **Play** control after playback completed.
- The orange page-connection-failed notice remained visible while the MP4 played.
- The task-created test tab was closed; pre-existing tabs were preserved.

## Scope and test status

This was a **5-second installed-app smoke only**, not long-form or YouTube-preview accounting. Source-only tests passed **2/2** for local MP4 readiness and WebGL context, and **25/25** `BrowserNavigationFeedbackTests` for the stale-failure guard. **At the time of this 2026-11-07 check**, that guard was not installed; no changed runtime was claimed in that check. The 2026-11-08 installed-build verification is recorded below.


## Recheck after stale-banner fix — 2026-11-08 KST

- Source commit: `e93b526`; focused `BrowserNavigationFeedbackTests`: 26/26 passed.
- Installed app: `/Users/rogan/Applications/3F Browser.app`, build 20, executable SHA-256 `72a9e93654a48e27fb17d8516fafe00017ff691c2a5c0bf7ca28f79c3bc300c3`; strict codesign and `workflow-control verify-mac` passed.
- Visible UI: muted MP4 reached 00:05/00:05; the previous orange connection-failed banner was absent.
- Focus Fence protection was disabled during local development, per direct user authorization. Other 3F TODOs remain open.
