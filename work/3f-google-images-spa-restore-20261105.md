# Google Images policy filter: SPA restoration

## Source change

- The result filter now saves the complete original inline `style` attribute before hiding a result and restores that exact attribute when the result becomes allowed.
- The filter synchronously reevaluates on `history.pushState`, `history.replaceState`, and `popstate`.
- Leaving a search-results route removes the query gate and restores filtered cards; detached filtered nodes are pruned from the retained set.
- Existing prepaint gate remains limited to Google Images (`tbm=isch` and `udm=2`) searches. Ordinary search/navigation behavior remains unchanged.

## Validation

- `swift test --filter FocusFenceSearchResultFilterTests` passed 7/7, including a JSCore journey for blocked → allowed → blocked query, push/replace/popstate, route away, and exact inline style restoration.
- `git diff --check` passed for the two owned files.
- Focused test compilation reused the existing `.build` output through `storage-guard`; approximately 48–49 GiB remained free.

## Delivery state

- Canonical branch `main`, base `69638fecfa46ad041c0b1f224cffc69a41d682a6`.
- Changed files: `Sources/ThreeFBrowser/FocusFenceSearchResultFilter.swift` and `Tests/ThreeFBrowserTests/FocusFenceSearchResultFilterTests.swift`.
- Source is uncommitted because repository integration is still held by another task's YouTube policy-feedback edit lease. No other task files were changed.
- Installed 3F UI and real Google results remain unverified; current CUA inventory exposes no task-owned isolated AI-only desktop/session. YouTube actual playback, account-sync read-after-write, and Windows receiver acceptance are separate open gates.


## Current candidate install readback — 2026-11-05 11:52 KST

- Source remains canonical `main@6c6925777afacd983f71bcca722b07aa475850bc`; the indexed Google Images rules candidate +16 is installed at `/Users/rogan/Applications/3F Browser.app` with executable SHA-256 `5130d14c2a4a790b273af537b850dd56a877d9252522aa1633068670b7062b8d`.
- Installation/signature readback passed; app was not launched. Search-result visibility in a live 3F window remains unverified because no isolated UI route is available.

## Canonical integration correction — 2026-11-05

The earlier statement that this source was uncommitted and awaiting an integration lease is historical and superseded. The SPA restoration change is committed as `226d1cf`; follow-up coverage is in `1399922` and `5be8b18`, and the later preindex/adult-context changes are in `6c69257` and `73175c6`. All are ancestors of the build17 source `82a5706`. The note remains useful as test and delivery evidence; actual installed live Google results rendering is still unverified.
