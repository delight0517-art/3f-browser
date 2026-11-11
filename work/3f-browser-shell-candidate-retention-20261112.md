# 3F CEF candidate retention receipt — 2026-11-12 KST

- Canonical source: `/Users/rogan/appDev/apps/3f-browser-mac`, main branch.
- Reused build tree: `.build/cef-156-arm64/cefsimple-isolated-build`.
- Kept diagnostic bundles: `.build/3f-cefsimple-browser-shell-candidate` and v2 through v6 (about 330 MiB each). None has verified persistent-window/page-load runtime, so each remains an unverified evidence candidate; no superseded candidate was retired.
- Installed 3F Browser build20 and the two Nov 8 rollback backups were not changed.
- Exact process check: no `cefsimple` or CEF helper remained after the v4 launch; `lsof +D` found no open file under the v4 bundle.
- No user profile, session, or authentication data was deleted. Diagnostic CEF profiles are separate and preserved.
- The v5/v6/v7 rebuilds reused the same CEF build tree. The final `delivery-proof capacity --after` read was 51.37 GiB free; the 20 GiB reserve remains satisfied.

- Build20 rollback verified: bundle version 0.1.0 (20), deep/strict signature valid, executable SHA-256 `dff7c101c2f57b4d5f8bc0e9b8049fb3c982531992d7e313b978553daf2fe188`; installed build20 hash differs and was not modified. The Nov 8 09:53 backup remains within its 14-day window, expiring 2026-11-22 09:53:04 KST; retained.
