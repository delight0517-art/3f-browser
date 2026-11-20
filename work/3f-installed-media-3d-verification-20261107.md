# 3F installed media / WebGL verification checkpoint

- Date: 2026-11-07 KST
- Repository: `/Users/rogan/appDev/apps/3f-browser-mac`, base/source observed at `df283e3f5f0131d22bf82dc1de518d93c8066f8c`.
- Scope: resume saved installed-app video-seek and 3D/WebGL proof; preserve all pre-existing dirty and untracked paths.
- Ownership: `agent-coord` edit lease `d825c70e-49d7-4131-ba7f-3c50be3960e6`, exact paths `BrowserWebView.swift`, `ThreeFBrowserControl.swift`, `ThreeFBrowserControlTests.swift`, `TODO.md`, and this checkpoint. No source change was made in this slice.

## Policy/controller diagnosis evidence

- Embedded controller status at 2026-11-07 21:25 KST: `about:blank`, `controlAvailable=true`; ARIA and read both refuse with “Focus Fence 정책을 확인할 수 없어 브라우저 접근을 중단했습니다.” No navigation was attempted.
- Direct read-only `GET http://127.0.0.1:17361/rules?browser=3f`: HTTP 200, JSON, 1,303,761 bytes; `blockedDomains`, `blockedUrlParts`, `keywords`, and `blockExceptions` are arrays of strings. `/health` is also HTTP 200 but is not authorization evidence.
- 3F source `ThreeFBrowserControlController.fetchFocusFenceRules()` constructs exactly `/rules?browser=3f`, uses GET, 2-second timeout, no-cache, and accepts HTTP 200; `usableFocusFenceRules` requires the four arrays above. This agrees with the direct response. No source-level fetch/contract mismatch is proven.
- `/usr/bin/log show --last 15m --style compact --predicate 'process == "FocusFence"'` shows FocusFence PID 717 serving successful loopback requests on port 17361, including the large rules response; logs also show listener endpoint warnings but no policy-contract rejection identified. PID 717 is launched from `/Applications/Focus Fence.app`; bundle version 1.0.6, build 2026110402. Focus Fence was not restarted and rules were not changed.
- Narrow fail-closed test: `/usr/bin/swift test --filter ThreeFBrowserControlTests` passed 18/18, including unavailable-policy rejection and valid rules decision tests. This is source test evidence only.
- Diagnosis remains unresolved: despite direct service and source contract agreement, embedded controller still rejects policy. The embedded implementation's internal status contract is not present in this repository and its private logs/status are not exposed by the available embedded tools. Do not infer that HTTP 200 is controller authorization.

## Installed runtime evidence and remaining gap

- Existing receipt `work/3f-webkit-video-webgl-installed-runtime-20261107.md`: installed 0.1.0 build 18 showed a 5-second MP4 reaching 00:05/00:05, but no seek action was exercised; get.webgl.org showed WebGL support and a visible spinning cube. This is historical short smoke, not current-session verification.
- Required fresh installed-app video playback + seek and actual 3D/WebGL preview remain outstanding. The current embedded UI route is policy-closed; do not bypass Focus Fence. Retry only after the embedded controller can verify policy. No runtime success is inferred from `/health`, `/rules`, source tests, or the prior smoke.
- Next: obtain controller-side policy-status contract/log evidence through the authorized embedding implementation/support path; then, only if its policy check succeeds, perform installed-app playback and seek plus actual visible 3D/WebGL preview. Continue other 3F TODOs independently; this task is not complete.


## Broader TODO source checks (2026-11-07)

- Read all unchecked TODO headings and `integration-backlog list --repo /Users/rogan/appDev/apps/3f-browser-mac`. Remaining work includes policy-gated installed UI checks (fresh video seek/WebGL, stale banner, default-browser runtime, YouTube preview, snooze runtime), product/receiver decisions or Windows runtime parity, and broader CEF migration. These cannot all be closed by source-only changes.
- `swift test --filter BrowserNavigationFeedbackTests` passed 25/25, including late failure after successful navigation, current-navigation failure behavior, Focus Fence unavailable ordinary HTTP allowance, and policy-fail-closed distinctions. The TODO now explicitly keeps installed stale-banner verification pending because no policy-authorized UI route is available.
- `swift test --filter MediaSiteSnoozeStoreTests` passed 2/2, covering store-instance persistence, subdomain matching, exact 24-hour expiry, and expired-entry removal. TODO now records this fresh source evidence while leaving normal installed relaunch/re-prompt verification unchecked.
- These are source-level checks, not installed-app proof. No files under Sources or Tests were modified in this continuation; existing dirty paths were preserved.
