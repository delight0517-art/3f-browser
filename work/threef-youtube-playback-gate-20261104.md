# 3F YouTube page access with quota playback stop

- Owner: Codex thread `01a19801-5652-7ac3-b2bc-2760e58a7122`
- Source repository: `/Users/rogan/appDev/apps/3f-browser-mac`, base `b9c3e1cc28f5e48f802c7877e423c626619e0aa3`, existing `main` branch.
- User scope: keep YouTube pages available in 3F while Focus Fence quota blocks playback; defer Firefox reactivation until its browser plugins are complete.

## Change

- Enabled only `OptionalFeatureAvailability.youtubeUsageReporting` in 3F. Focus Fence site-navigation enforcement and preview blocking remain off.
- Advanced the app build to `0.1.0+5` and added a regression assertion that the quota-aware reporter is enabled.
- Existing navigation test covers YouTube page access when only the playback quota is blocked; the reporter pauses YouTube video when policy is blocked and fails closed when policy cannot be read.
- Updated `TODO.md` with the pending Firefox reactivation gate.

## Verification

- `node scripts/test-youtube-usage-reporter.js`: 7 assertions passed.
- `swift test --package-path /Users/rogan/appDev/apps/3f-browser-mac --build-path /Users/rogan/appDev/apps/3f-browser-mac/.build`: 83 tests passed, 0 failed.
- `git diff --check`: passed.
- Live Focus Fence readback: `/rules?browser=3f` returned `youtubeQuotaBlocked=true` and no `youtube.com` host in `blockedDomains`; `/usage/youtube` returned 1,201 seconds against a 20-minute daily cap and `blocked=true`.
- Installed 3F `0.1.0+5` opened the YouTube home and a public Big Buck Bunny page. With the daily quota blocked, the player remained at 0:00 with its Play control visible after a play attempt; the 3F UI showed `오늘 시청 20분 1초 · 한도 20분 · 재생 제한 중`. Usage stayed at 1,201 seconds and did not record 3F playback.
- Installed bundle passed `codesign --verify --deep --strict`; installed executable SHA-256: `e0c9f7d1064d76ab11ad11544e71cbf6dfc242e338ffd6e89a73990a67f92c83`.

## Delivery and remaining boundary

- The previous installed `0.1.0+4` is retained as the single managed rollback at `/Users/rogan/Library/Caches/CodexManagedArtifacts/app-backup-com.rogan.threef.browser-20261103T143543Z-79482-50a91687`.
- Removed the temporary pre-update bundle and older in-Applications rollback after the new install and runtime check succeeded.
- Firefox extension activation, Windows behavior, and cross-device parity remain pending. No system-wide YouTube DNS/hosts rule was added or removed.
