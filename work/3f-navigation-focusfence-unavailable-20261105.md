# 3F ordinary navigation during Focus Fence outage — 2026-11-05

## Change

- When the local Focus Fence endpoint cannot be reached or returns a non-200 status, allow only ordinary HTTP/HTTPS URLs with a nonempty host so 3F remains usable during the service outage.
- When HTTP 200 returns malformed rules, keep navigation unavailable/fail-closed. When valid rules are returned, continue using the exact existing block-domain, URL-part, keyword, exception, and YouTube-quota decisions.
- The YouTube playback reporter still fails closed when policy is missing; page navigation availability does not permit untracked playback.

## Validation

- `swift test --filter BrowserNavigationFeedbackTests` — 20/20 passed. Coverage includes HTTP/HTTPS allow on missing policy, file/javascript refusal, malformed-rule fail-closed, valid domain/path blocks, and YouTube quota-specific decision behavior.
- `git diff --check` passed.

## Integration and runtime limits

- Source edits are limited to `ThreeFBrowserControl.swift`, `ThreeFBrowserApp.swift`, and the focused navigation test file. Canonical `TODO.md` is currently held by active exact-path lease `5c312ce3` from task `3f-google-images-windows-parity-20261105`; no TODO edit was made.
- The existing installed browser was not restarted or changed. Installed navigation during an actual Focus Fence outage remains unverified without a task-owned isolated UI session.
- Focus Fence YouTube usage/account sync and Windows receiver parity remain separate open requirements.

## Build output retention

- Reused the existing `/Users/rogan/appDev/apps/3f-browser-mac/.build` Swift test cache (about 4.0 GiB logical size); no candidate app bundle or separate build output was created.
- Kept all existing candidates and the running installed app unchanged. Free space was 47.65 GiB before the focused build/test and was rechecked after it.
