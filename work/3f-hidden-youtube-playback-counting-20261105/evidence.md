# 3F hidden-tab YouTube playback counting

## Change

- Removed document-visibility gating from playback-time measurement. The reporter still requires an active, progressing YouTube video, so an idle hidden page does not accrue time.
- Updated the focused reporter harness to require exact measured time from a hidden background tab.

## Validation

- `node scripts/test-youtube-usage-reporter.js` — passed: `YouTube usage reporter account-lease playback, outage fallback, interval, retry, privacy, and quota checks passed`.
- `git diff --check -- Sources/ThreeFBrowser/YouTubeUsageReporter.swift scripts/test-youtube-usage-reporter.js` — passed.

## Limits

- Synthetic reporter validation only. Installed +10 runtime, local Focus Fence service, production account-ledger write, and Windows parity are not verified.

## Candidate build and UI/runtime gate

- Built 0.1.0+11 to `.build/youtube-background-playback-candidate-20261105/3F Browser.app` using an isolated Swift build directory; executable SHA-256 `8d5614e88a72de993abfd56acb19d780419d2a32cbe6c7d709f0bee8ad09d182`.
- `codesign --verify --deep --strict` passed and `workflow-control verify-mac` returned `launchAllowed=true`, `mode=local_dev`.
- No task-owned AI-only desktop/session was exposed in the CUA inventory; therefore the app was not launched or installed and no new real playback was attempted. Current installed version remains 0.1.0+9.
- Production account-budget `/grant`, `/report`, and `/state` routes returned 404 in the latest available anonymous probes. Windows runtime/account parity and schedule synchronization remain unverified.
- Retention receipt: `work/3f-hidden-youtube-playback-counting-20261105/retention-receipt.md`.

## Follow-up hidden timer-throttling fix

- Commit `702e928` raises the allowed sampling gap to 120 seconds only while the page is hidden; the reporter still checks video playback state, source continuity and media-time progress against elapsed wall time. Visible-page tolerance remains 15 seconds.
- Focused Node harness passed including: visible/hidden progress, 20-second throttled hidden timer reporting exactly 20 seconds, and exclusion of a 180-second suspended gap.
- Built candidate 0.1.0+12 at `.build/youtube-hidden-throttled-candidate-20261105/3F Browser.app`; executable SHA-256 `59e08cab1c28b1891b4ed248c178554484028d758b901a51160eeca0ebad573d`; strict code signature and local-dev verifier passed.
- Installed bundle remains 0.1.0+9. Updating is currently held because two registered 3F app backups are unexpired; one is owned by another active work-share task, so neither was deleted. A fresh compatible AI-only UI desktop/session is also absent from the available CUA surface.
- Fresh read: local Focus Fence endpoints on port 17361 are not listening; anonymous production YouTube account-budget `/grant`, `/report`, `/state` return HTTP 404. No account-sync or new playback claim.

## Cross-platform handoff read

- The latest available Drive architecture contract is v1.9.0, updated 2026-11-04. It defines `usage.youtube_budget` around interval union/accounting semantics and explicitly separates platform adapters; Drive is not the live usage store.
- Its Windows Focus Fence row identifies candidate 1.0.0+684 and installed 1.0.0+657. This is Focus Fence evidence, not proof of the current Windows 3F Browser build or its live usage ledger.
- Local 3F handoff documents prior Windows 3F YouTube UI behavior and Firefox-default 180m/day + 10m/hour policy where custom account policy was absent. It does not establish the user's current custom policy on Windows or Mac.
- The live Mac 3F consumer currently reads Focus Fence loopback `/usage/youtube`; that service is not listening in this check. The documented shared account API route is unavailable at production (`404`), so cross-device count and personal schedule read-after-write remain open.

## Account sync visibility follow-up

- Commits `64d7f9b` and `6933e06` parse the Focus Fence aggregate `cloudSignedIn` and `accountBudget.available/fresh/enabled` fields, display a compact sync state first in 3F's YouTube toolbar status, and keep detailed state in its help/accessibility text. No account name/email is displayed.
- `swift test --filter YouTubeUsageSummaryTests` passed 6/6 after both changes; new cases cover current, stale and disconnected account states and verify account email stays hidden.
- Anonymous production GET to `/api/cloud-state/focus-fense` returns 401 (auth required); `/api/youtube-budget/state` and `/grant` return 404. No token was read and no personal schedule rows were fetched.
- These source changes are committed and compile under focused test build, but are not in an installed app bundle or visible runtime. Installed 3F remains +9; AI-only UI route and current-version backup slot remain unavailable. Windows remains unknown.

## Resume audit — 2026-11-05

- Re-read current 3F source at HEAD `6933e06`. `YouTubeUsageReporter.requestAccountLease` treats a 400 `invalid_youtube_lease_request` as local mode, and other unavailable/error responses also fall back to local counting; the local path continues to report measured seconds through Focus Fence `/ingest`. Therefore anonymous production `/api/youtube-budget/{grant,report,state}` 404s establish that the account-lease path is unavailable at that endpoint, but do **not** by themselves prove that local YouTube tracking is broken.
- The 3F account path is: browser script → Focus Fence loopback `/youtube/budget/grant` and `/report` → authenticated server API. The separate interval-sync adapter writes `focusFenseYoutubeBudgetV1` through authenticated `/api/cloud-state/focus-fense`. Anonymous `GET /api/cloud-state/focus-fense` returned 401; anonymous YouTube grant/report/state probes returned 404. These checks do not use stored account credentials.
- The active shared parity contract is v1.38.0 (2026-11-05). It requires 30-second account leases and unioned measured playback intervals across clients, but says activation requires all clients to validate the versioned schema. The Mac 3F source validates schema 3 and uses 30-second leases. This is source/contract compatibility only; Windows runtime version, schema use, and cross-device read-after-write remain unverified.
- A separate contract capability currently describes foreground-only measurement with hidden tabs excluded, while the recent 3F commits count hidden-tab playback when media progress is verified. This is a policy mismatch requiring reconciliation with the canonical YouTube accounting requirement before claiming exact parity.
- No source files were changed in this continuation. Installed Mac remains +9; +13 candidate is not installed. No isolated AI-only UI session is exposed, backup retention cap remains full, local Focus Fence service is stopped, and Windows availability is unknown/expired. No app UI or remote Windows operation was attempted.

## Cross-device receiver readback — 2026-11-05

- Re-fetched the shared Windows handoff `FF-WINDOWS-TASK-STAR-DESK-PRIMARY-DISPLAY-YOUTUBE-BUDGET-2026-11-04.md` from Drive (file ID `1kfNIv93SfJHIIi4dz0oVD24FAku51nNH`; provider modified 2026-11-04 13:06 UTC). Its latest appended entry records StarDesk agent-controller XPC error 4099 and no verified primary-display access. The document still has no Windows receiver ACK, current installed Windows YouTube budget readback, or cross-device usage round-trip.
- Its Mac-side investigation says the Brainwire repo has an authenticated YouTube budget router in a dirty local checkout but production rollout/durable configuration was not established. Thus source presence does not resolve the live 404 responses.
- Current Mac `UsageIngestServer.swift` source now accepts `browser=3f` for local `/youtube/budget/grant` and `/report`, and delegates to authenticated cloud calls. This differs from an earlier Nov 4 handoff snapshot that said these routes accepted Firefox only; current source inspection supersedes that older snapshot for source behavior, but not installed/runtime behavior.
- Current contract v1.38.0 capability text for browser usage excludes hidden tabs; recent 3F commits explicitly count hidden-tab playback. Keep this mismatch open pending an authoritative accounting-policy resolution; do not call this exact Windows parity.

## Fresh focused/runtime path check — 2026-11-05

- Re-ran `node scripts/test-youtube-usage-reporter.js` at HEAD `6933e06`; it passed playback accounting, account-lease/outage fallback, interval, retry, privacy, and quota checks. This is source-level harness evidence, not a current app playback session.
- Fresh local probes to `127.0.0.1:17361/health` and `/usage/youtube` both failed with connection refused; no Focus Fence process/CLI was found by the bounded process/path check. Thus the local fallback cannot currently be exercised against a live Mac consumer service.
- Fresh anonymous production probes: grant/report/state all HTTP 404; authenticated cloud-state path gives HTTP 401 without credentials. No credentials were used.
- Correction to receiver status: a separate 2026-10-28 Drive receiver record (file ID `1kkFWenbEi6ZMPjNh7IhIRNPyaYxcuMz8`) is an ACK of Windows **source mapping** for `focusFenseYoutubeBudgetV1` and contract receipt. It explicitly says installed +657 remains distinct from candidate +684, no live account request/write occurred, and no installed Mac/Windows runtime or shared round-trip was proven. The separate 2026-11-04 parity task still has no current-runtime or usage readback.

## Local fallback → shared interval path — 2026-11-05

- Current 3F source has a local fallback: when the account lease endpoint is unavailable, it reports measured seconds to the Focus Fence loopback `/ingest`. The Focus Fence handler validates/attributes that report and `YouTubeUsageService.record` persists playback intervals.
- The Focus Fence `ScheduleSyncTimer` calls authenticated `syncYoutubeUsage` and `syncYoutubeBudgetIntervals`; the latter revision-CAS merges `focusFenseYoutubeBudgetV1` using interval union. The authenticated endpoint path is `/api/cloud-state/focus-fense`, distinct from the unavailable `/api/youtube-budget/*` lease routes. Thus local counting and eventual shared interval sync can operate through a different backend path; this is source architecture only while the local service is stopped and account auth is not read back.
- Render read-only inventory: production `brainwire-f2gf` service ID `srv-da2fudtg1s2s73cmrf9g`, Node/free plan, one instance, repo `delight0517/brainwire-app`, latest live deploy commit `16ba21d609dfacfed28284dd4b064e94273a1cdf` from 2026-10-30. No Render Postgres instance was listed and the service summary lists no persistent disk. Local YouTube lease routes remain untracked dirty source and are absent from this deployment; no deploy was triggered.
- The 2026-10-20 Focus Fence TODO explicitly records a user-approved background-tab measurement contract (media-progress validated; minimized window excluded). This supports the recent 3F hidden-tab implementation. The newer v1.38.0 capability description says hidden tabs excluded, so the documents conflict; do not silently revert the user-approved background behavior or claim exact platform parity until the current contract owner reconciles it.
- Historical runtime: installed 3F +9 previously played a video for 50 seconds and Focus Fence counters advanced 49 seconds. This proves the older local fallback runtime worked then; it does not prove current source +13, current service, account lease, or Windows sharing.

## End-to-end source route trace — 2026-11-05

- Confirmed current code path details: 3F local fallback posts to Focus Fence `/ingest`; `attributeUsage` validates host/browser/report ID, and `YouTubeUsageService.record(browser:seconds:playing:reportID:at:)` persists a playback interval. `ScheduleSyncTimer` uploads intervals via `syncYoutubeUsage` and writes the account-wide union in `focusFenseYoutubeBudgetV1` through authenticated `/api/cloud-state/focus-fense` CAS. This is distinct from schema3 `/api/youtube-budget/*` leases.
- Windows source receiver ACK 2026-10-28 maps and tests the same `focusFenseYoutubeBudgetV1` interval-union field. It explicitly leaves installed +657 separate from candidate +684 and has no live BlueCloud read/write. Therefore source-level Mac/Windows field compatibility exists; live account sync and enforcement do not yet have proof.
- Current blockers for that end-to-end journey are the stopped Focus Fence local service, absent isolated AI-only Mac UI destination, and lack of fresh Windows runtime access. No 3F or Focus Fence source edits, app launches, installs, quota mutations, or production deploys were made this continuation.

## Current installed/candidate verification — 2026-11-05

- Installed `/Users/rogan/Applications/3F Browser.app`: `0.1.0+9`, executable SHA-256 `9b4d7dfb31d93f18da01ab1e1e9db6fbd72802dc5e515da7bef3cdef1dce00e4`; `workflow-control verify-mac` returned `verified`, `launchAllowed=true`, `local_dev`.
- Current candidate `.build/youtube-account-sync-candidate-20261105/3F Browser.app`: `0.1.0+13`, executable SHA-256 `a9f0c0896fe0d3d7f2511c59ad750a92cbb498a0db736366a88402797536b0a1`; verifier also returned `verified`, `launchAllowed=true`, `local_dev`.
- Recovery-copy inventory remains at its maximum of two registered, unexpired copies; one is owned by another active task. No copy was removed and no install was attempted.
- Fresh CUA inventory again lists ordinary apps but no isolated AI-only desktop/session. Configured `/Users/rogan/.codex/bin/mac-doctor` symlink points to a missing script target; no diagnostic was obtained. A mistaken `/Applications/3F Browser.app` inspection created no bundle or file; the actual installed bundle above was read successfully.
- No new UI playback proof. Historical +9 playback evidence remains scoped to +9; candidate +13 remains uninstalled. Windows availability is expired/unknown and no remote operation was attempted.

## Fresh runtime recheck — 2026-11-04 23:50 UTC / 2026-11-05 08:50 KST

- `node scripts/test-youtube-usage-reporter.js` passes at current `main` HEAD `d464442`.
- Installed Mac app still reads `0.1.0+9` / executable SHA-256 `9b4d7dfb31d93f18da01ab1e1e9db6fbd72802dc5e515da7bef3cdef1dce00e4`. The existing +13 candidate remains `a9f0c0896fe0d3d7f2511c59ad750a92cbb498a0db736366a88402797536b0a1`; HEAD changes since its build are documentation only (`git log` confirms latest commits touch TODO/work evidence, not reporter source).
- Focus Fence local `/health`, `/usage/youtube`, and `/rules?browser=3f` each returned HTTP 200. Usage snapshot reports YouTube unblocked, daily cap 20 minutes and hourly cap 10 minutes; `browserSeconds` is empty and last 3F browser observation is stale (2026-11-04T11:23:36Z). This establishes a live policy/service read, not a fresh 3F playback report or account interval read-after-write.
- CUA inventory shows 3F Browser is not running and exposes no isolated AI-only desktop/session. No app was launched and no playback or quota state was fabricated.
- Drive handoff `3F_GOOGLE_IMAGES_MAC_HANDOFF_20261105.md` (ID `17yZWFEkxfD_Pcd2AR6tfPV_Lgdmq3Pgx`) was fetched successfully. A separate active FF/3F task is handling Google Images parity; its exact edits are being left alone. Windows handoff itself says external Google results and `clientRuntimeVerified` were not verified there.

## Resume audit — 2026-11-05

- At this earlier point in the resume audit, CUA showed 3F Browser stopped and no isolated AI-only UI session. Later the same morning, 3F appeared under PID `85291`; see the live-accounting section below. Focus Fence was running, and 3F source HEAD was `d464442`.
- At this earlier Windows access check, no pinned key was found for the `winpc` host-key alias and the bounded scan returned no key. A later recheck found an ED25519 entry in `known_hosts` for `192.168.1.108`; strict read-only SSH to configured `.106` then failed `Host is down`, and direct strict SSH to `.108` failed `Connection refused`. No remote command ran; Windows runtime remains unverified.
- `agent-coord status` and `app-integration-guard check` for `/Users/rogan/appDev/apps/3f-browser-mac` report no active lease for this repository, while untracked work from other tasks remains preserved.

## Live installed playback-accounting signal — 2026-11-05

- Fresh CUA inventory now reports 3F Browser running. Process `85291` is the installed `/Users/rogan/Applications/3F Browser.app/Contents/MacOS/ThreeFBrowser`, started 09:04:01 KST; installed bundle remains `0.1.0+9`, executable SHA-256 `9b4d7dfb31d93f18da01ab1e1e9db6fbd72802dc5e515da7bef3cdef1dce00e4`, and `codesign --verify --deep --strict` passes. No UI was opened or controlled.
- Focus Fence Debug process `75760` serves port 17361. `/health`, `/usage/youtube`, and `/rules?browser=3f` responded. The usage API reported `browserSeconds.3f=126` at `2026-11-05T00:06:55Z`, then 157, then 204 with `browserUsageLastSeen.3f=2026-11-05T00:08:35Z`: +78 measured 3F seconds across the 100-second report window. The API labels its measurement `media-progress-playback-v3-unless-window-minimized`, with coverage stating observed playing-media progress. This is live runtime evidence that the installed +9 process is reporting advancing playback time; no video page or title was inspected.
- At 00:07:41Z, `/rules?browser=3f` reported `youtubeQuotaBlocked=false`, `youtubeBlockedByActiveSchedule=false`, and no YouTube/Googlevideo/ytimg blocked hosts. Current policy is 20 minutes daily and 10 minutes hourly. This confirms local Focus Fence policy currently allows YouTube while under quota.
- The same usage response reports `cloudSignedIn=true` but `accountBudget.available=false`; the authenticated interval-union cloud read-after-write remains unverified. This does not prove personal account sync.
- Candidate `0.1.0+13` remains present, strict-code-signature-valid, and accepted by `workflow-control verify-mac` (`launchAllowed=true`, `local_dev`), executable SHA-256 `a9f0c0896fe0d3d7f2511c59ad750a92cbb498a0db736366a88402797536b0a1`; it is not installed. No candidate playback proof was obtained.
- The AI-only UI inventory still provides no isolated destination, and the registered 3F backup limit remains full. Windows host-key/readback and receiver runtime remain unverified. Keep the goal open for candidate playback, authenticated Mac account interval read-after-write, and Windows receiver parity.

## Follow-up runtime and Windows reachability — 2026-11-05 09:14 KST

- CUA still reports 3F Browser running. PID `85291` remains the installed `0.1.0+9` executable (`9b4d7dfb31d93f18da01ab1e1e9db6fbd72802dc5e515da7bef3cdef1dce00e4`). Focus Fence Debug PID `75760` remains the local consumer on port 17361.
- `/usage/youtube` read at `2026-11-05T00:14:10Z` reported `browserSeconds.3f=466`, `todaySeconds=1045`, and `hourlyUsedSeconds=444`; at `00:14:20Z` it reported `471`, `1050`, and `449`. The 3F counter advanced by 5 seconds in 10 seconds, with both quota counters advancing. Measurement mode remains `media-progress-playback-v3-unless-window-minimized`; no YouTube page/title was inspected and Codex did not initiate playback.
- At the second sample the local usage values were 150 seconds below the daily cap and 151 seconds below the hourly cap, with `blocked=false`. No further quota-consuming playback was initiated. Actual cutoff/enforcement at the cap was not tested.
- SSH configuration maps `winpc` to `192.168.1.106` with `HostKeyAlias=192.168.1.108`. Strict `ssh ... winpc hostname` returned `Host is down`; strict direct SSH to `.108` returned `Connection refused`. Drive search still finds the latest Windows YouTube-budget handoff last modified 2026-11-04 13:06:19Z; no newer receiver ACK/readback was found.
- Candidate `+13` remains uninstalled, authenticated interval-union cloud read-after-write is unverified (`accountBudget.available=false`), and Windows policy/receiver parity remains open.

## Current quota-state read — 2026-11-05 09:28 KST

- Installed 3F `0.1.0+9` PID `85291` was still running. `codesign --verify --deep --strict` passed.
- Focus Fence Debug `/usage/youtube` returned `todaySeconds=1206`, `browserSeconds.3f=631`, `hourlyUsedSeconds=605`, `hourlyRemainingSeconds=0`, `blocked=true`, and measurement `media-progress-playback-v3-unless-window-minimized; legacy-playing-hint-fallback`. `/rules?browser=3f` returned `youtubeQuotaBlocked=true`, `youtubeBlockedByActiveSchedule=false`.
- This confirms that the installed reporter and local policy consumer show quota exhaustion/blocked state. No YouTube page/player UI was inspected in this check, so visible pause behavior is not newly verified. We did not clear counters or initiate additional playback.
- `accountBudget.available=false`; authenticated personal-account interval-union read-after-write and Windows receiver/runtime parity remain unverified.
