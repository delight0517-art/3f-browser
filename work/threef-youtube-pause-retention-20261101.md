# 3F Browser YouTube playback pause scope — retention receipt (2026-11-01 KST)

- Canonical source: `/Users/rogan/appDev/apps/3f-browser-mac`, branch `main`, HEAD `5eaaee0b9b391a0fed88ac2cbf22ddc426ed0d43`; existing dirty work preserved.
- Changed `YouTubeUsageReporter.swift` so quota blocking pauses video only on YouTube hosts, matching the server's `youtube.com`/subdomain and `youtu.be` policy while excluding `music.youtube.com`.
- Actual injected JavaScript exercised in a Node VM harness: 4 checks passed (unrelated video remains playing, unrelated play event remains unblocked, YouTube video pauses, YouTube Music remains unblocked). Full Swift package suite: 29/29 passed.
- Separate release app candidate: `.build/youtube-pause-candidate-20261101/3F Browser.app`, bundle `com.rogan.threef.browser`, build `2`, executable SHA-256 `8f81d00159b67c9160ab53aeb2393c263efb84a7b97f893f83e97158c439c3a1`; strict codesign and `workflow-control verify-mac` passed. It is not installed or launched.
- Preserved the prior session-restore candidate at `.build/session-restore-candidate-20261101/3F Browser.app`; no prior output was retired or overwritten in this slice. Installed 3F Browser and its current page remain untouched.
- Storage: 2 GiB guarded peak; 47.61 GiB free before, 47.60 GiB after, preserving the 20 GiB reserve.
