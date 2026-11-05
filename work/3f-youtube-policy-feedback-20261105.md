# 3F YouTube / Shorts policy feedback — 2026-11-05

## User request and observed cause

User requested Shorts policy/usage synchronization with the logged-in FF account, an explanation when YouTube fails to open/play, and visible remaining viewing allowance and time until restriction ends.

Read-only observations at this task start:

- FF `/usage/youtube`: `cloudSignedIn=true`, `accountBudget.available=false`, `todaySeconds=1206`, `dailyCapMinutes=20`, `blocked=true`; the rolling-hour window had expired to `hourlyUsedSeconds=0`, `hourlyRemainingSeconds=600`.
- FF `/rules?browser=3f`: `youtubeQuotaBlocked=true`, `youtubeBlockedByActiveSchedule=false`, `blockShorts=false`, `youtubeQuotaResetAfterSeconds=51714` at that read. No YouTube domain/path block was returned.
- System DNS resolved YouTube to public addresses; YouTube HTTPS returned200. This excludes a system DNS/hosts outage at that read, not every WebKit/page-loading error.
- The installed 3F authenticated control descriptor responded with `ok=true`, `ready=false`, empty title and `about:blank`. No user page navigation was sent. This does not prove the user's YouTube page loaded or that every loading failure is quota-related.
- Production account-budget `GET /api/youtube-budget/state` and `POST /api/youtube-budget/grant` returned404. FF login alone therefore does not establish shared account-lease availability. The existing isolated backend ledger/HTTP/auth/SQLite test suite passed, but its source task explicitly leaves production configuration/deployment pending.

## Integrated source

Commit `71b9ae6` on canonical 3F main:

- Usage client reads aggregate usage and the shared FF rule metadata, including Shorts block, active-schedule reason and quota reset delay. Unknown/malformed reset data remains unknown rather than fabricating zero wait.
- A multi-line native YouTube status panel shows consumed time, remaining allowance, reason for restriction, and a per-second countdown using FF's observed reset deadline. Expired cached data says the limit is being rechecked instead of claiming playback is allowed.
- A rejected YouTube destination remains a policy/usage context, so a blank or previous page no longer prevents the panel/poller from showing restriction information.
- Known network/DNS/TLS/timeouts receive specific messages; generic connection failure does not falsely assert a quota cause.
- Shorts playback remains part of the same YouTube time meter. The reporter now consumes the shared `blockShorts` flag and pauses Shorts under that policy. Same-document transitions back to ordinary videos do not retain a Shorts-only block. Existing daily/hourly quota enforcement and local fallback remain in place.
- Login and shared-account budget availability are described separately; no sync success is invented.
- Source build version is `0.1.0+14`. Installed app is still the user's existing build until an explicit safe install/readback boundary.

## Verification

- `swift test`:125/125 passed, including six new policy/countdown/rejected-navigation/client-fetch tests and all existing navigation/usage tests. Log: `/Users/rogan/Documents/Codex/2026-11-01/x20-3/work/3f-youtube-policy-feedback-tests-20261105.log`.
- `node scripts/test-youtube-usage-reporter.js`: existing measured playback/hidden tab/lease/retry/fallback/privacy cases plus actual simulated Shorts playback, Shorts-only block and SPA transition cases passed.
- `node --test server/tests/youtube_budget.test.js` in canonical Brainwire: isolated account union, clipping, qualified lease boundary, retry/idempotency, durable restart, concurrent SQLite and HTTP auth checks passed. No production account write was made.
- Owned source diff checks passed. No current browser session, FF preference, credentials, volume, or user desktop was changed.

## Remaining delivery

Use one signed candidate output and preserve the installed browser/session. Product build/install and visible runtime are separate from the passing source/SwiftUI compilation tests. No task-owned isolated AI UI destination has been evidenced for this task.

Production shared-account synchronization remains incomplete. Render exposes a single candidate workspace `My Workspace` for the connected account, but its tools require the user to confirm the workspace before reading service configuration. An existing Render workspace handoff already exists in another task, so no duplicate alert is created. The clarification in this chat can also establish the intended destination. Deployment is a separate action after exact source/Node/durable-single-authority storage/capability prerequisites are verified; no new disk purchase or production mutation is authorized by this report.
