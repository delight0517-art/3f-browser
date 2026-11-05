# 3F Google Images address-directory filter — 2026-11-05

## Windows handoff

- Drive file `3F_GOOGLE_IMAGES_MAC_HANDOFF_20261105.md`, ID `17yZWFEkxfD_Pcd2AR6tfPV_Lgdmq3Pgx`, was fetched back successfully.
- The handoff expects `tbm=isch` and `udm=2`, policy-based hiding for address/link directory queries before results paint, restoration of allowed image queries, and ordinary web search left visible.
- Current Mac source at starting HEAD `ac9e993` recognized only `tbm=isch`; it evaluated result cards after page completion and had no query prepaint gate.

## Mac source implementation

- Added a WebKit document-start gate for Google image-search routes using either URL parameter. It hides the page content until Focus Fence rules are available.
- Added a query classifier using the existing shared keyword list and address/link/directory phrasing. A blocked query keeps results hidden behind an in-page policy notice; an allowed query releases the gate. `popstate` and DOM updates re-evaluate the query.
- Extended URL and result-card classification for `udm=2`. Ordinary Google web search is outside the gate.

## Source validation

- `swift test --filter FocusFenceSearchResultFilterTests` — 6/6 passed. This includes JSCore execution of the document-start gate for both `tbm=isch` and `udm=2`, no gate on ordinary search, configured `주소모음` / `링크 모음` terms, address-directory and adult-directory queries, allowed image queries, existing destination classification, and rule validation.
- `git diff --check` passed.
- No product build/install or live Google page was launched. No task-owned isolated AI-only UI route was available, so installed 3F rendering and real Google result transitions remain unverified.

## Current YouTube runtime cross-check

- Installed `0.1.0+9` process PID `85291` was still running at 09:28 KST; `codesign --verify --deep --strict` passed.
- Focus Fence Debug `/usage/youtube`: `todaySeconds=1206`, `browserSeconds.3f=631`, `hourlyUsedSeconds=605`, `blocked=true`; `/rules?browser=3f`: `youtubeQuotaBlocked=true`, `youtubeBlockedByActiveSchedule=false`. This shows the local policy consumer has reached its daily/hourly quota state; it does not expose the current YouTube player UI.
- Earlier direct visual playback proof (installed +9, 50 seconds) and isolated +10 cutoff proof remain in the existing receipts named in `TODO.md`.
- Authenticated personal account interval-union read-after-write remains unavailable (`accountBudget.available=false`); Windows account-budget receiver/runtime parity remains unverified.
