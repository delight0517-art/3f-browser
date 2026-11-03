# 3F navigation-feedback candidate retention

- Task: `3f-navigation-feedback-20261101`
- Preserved release build: `/Users/rogan/appDev/apps/3f-browser-mac/.build/navigation-feedback-release-20261101` (107 MiB).
- Preserved signed candidate: `/Users/rogan/appDev/apps/3f-browser-mac/.build/navigation-feedback-candidate-20261101/3F Browser.app` (2.9 MiB; bundle `com.rogan.threef.browser`, version `0.1.0+2`, executable SHA-256 `335d0e615f876b76ff8e23088676e88f0665600e33a686667a92f84f779c7532`).
- Both are retained as uninstalled, unverified candidates for this task. No older output was removed; existing candidate paths were left untouched.
- The live production app and its default-browser/session verification are owned by task `01a19470`; installing or launching this same-bundle candidate now could displace its active work. This candidate is not declared disposable and has no expiry registration.
- All 59 3F Swift tests passed before candidate packaging. Signature verification and `workflow-control verify-mac` passed. Visible app/runtime behavior remains unverified.

## Authorization outcome feedback follow-up — 2026-11-01

- New source distinguishes `blocked` from Focus Fence `unavailable`; the visible notice now says whether a rule/YouTube viewing limit rejected the page or Focus Fence failed to respond. This does not bypass either decision.
- Focused navigation-feedback tests pass 5/5 and the full Swift package suite passes 60/60.
- New signed production-ID candidate: `/Users/rogan/appDev/apps/3f-browser-mac/.build/navigation-reason-candidate-20261101/3F Browser.app`, executable SHA-256 `d8e01726b4c08813cf814970ee6ee6132d114ef0c06560ffb453ffe880577763`; strict signature verification and local build launch check pass. It remains unlaunched and uninstalled because the active production 3F session is owned by another task. The older candidate and its release directory were preserved.
- Disk check after build: 34.20 GiB free. No generated output was deleted.

## Exact YouTube versus host readiness reason — 2026-11-01

- The `/rules` payload's `youtubeQuotaBlocked` signal is now mapped to a separate 3F navigation decision when a YouTube host is denied. Rules denial, YouTube protection state, and unavailable FF connection produce distinct Korean notices. This is explanatory UI; the FF decision is still enforced.
- Full package tests now pass 62/62, including YouTube quota reason plus allowed Gemini and Drive navigation decisions. Focused navigation feedback suite is included in that total.
- Latest candidate: `/Users/rogan/appDev/apps/3f-browser-mac/.build/navigation-feedback-final2-candidate-20261101/3F Browser.app`; executable SHA-256 `1d79aa7183c6c2f130de16f41c07e7e114897fce6b7501d219dd72b5733b198b`. It passes strict signature verification and `workflow-control verify-mac`; still uninstalled/unlaunched due active production-session ownership.
- Latest post-build disk check remains 34.23 GiB free. Prior candidates/release folder remain preserved pending install and consumer proof; no generated outputs were deleted.

## 2026-11-01 loading-feedback QA candidate

- Built current Swift package source in isolated `.build/qa-navigation-feedback-20261101/build`, then packaged `.build/qa-navigation-feedback-20261101/app/3F Browser QA.app` with QA-only bundle ID `com.rogan.threef.browser.qa.20261101`, a QA display name, and no URL scheme handlers. Executable SHA-256: `46234890a1bac75eafed2638457a987c61136f75cc63316ad9c63d2f67795fee`.
- The source package suite passed 68/68 on 2026-11-01 18:07, 18:09, and 18:14 KST. Rebuilt the current-source Release executable after YouTube telemetry URL removal, explicit Enter-equivalent quicklink copy, and the Focus Fence launch-versus-page-navigation status clarification; current executable SHA-256: `82b4ab9ec03b0b3f86ed6ff71ee57a698e8cee5176317ad32b3e0769c65601d1`. Deep/strict codesign and `workflow-control verify-mac` passed. The earlier isolated process exited with signal 15 / status 143 before a window could be inspected; no app UI result is claimed. This QA bundle is not covered by the production 3F app exception and cannot validate that path.
- The temporary HOME and control-descriptor folder was removed by the Python exit trap. The QA build output remains as the task-owned artifact for this attempted runtime check; production-ID candidate paths and active app ownership were untouched.

## YouTube telemetry minimization follow-up

- 3F usage POST now sends host, browser, report ID, elapsed seconds, watched seconds, and playing state; it no longer sends the full YouTube URL (which can include a video ID or query).
- Focus Fence's ordinary usage path persists aggregate seconds and browser only. Shorts-event URL validation remains available for clients that submit `shortsEventId`; 3F does not submit that field, so the removed URL is not needed for this reporter.
- `node scripts/test-youtube-usage-reporter.js` passes seven checks, including a synthetic playback interval and an exact aggregate-only payload key assertion. Swift parser and Node syntax check pass. No app build/install/runtime claim added.
