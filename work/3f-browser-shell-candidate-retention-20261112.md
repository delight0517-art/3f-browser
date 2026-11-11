# 3F CEF candidate retention receipt — 2026-11-12 KST

- Canonical source: `/Users/rogan/appDev/apps/3f-browser-mac`, main branch.
- Reused build tree: `.build/cef-156-arm64/cefsimple-isolated-build`.
- Kept diagnostic bundles: `.build/3f-cefsimple-browser-shell-candidate`, `...-v2-candidate`, `...-v3-candidate`, and `...-v4-candidate` (about 330 MiB each). None has verified persistent-window/page-load runtime, so each remains an unverified evidence candidate; no superseded candidate was retired.
- Installed 3F Browser build20 and the two Nov 8 rollback backups were not changed.
- Exact process check: no `cefsimple` or CEF helper remained after the v4 launch; `lsof +D` found no open file under the v4 bundle.
- No user profile, session, or authentication data was deleted. Diagnostic CEF profiles are separate and preserved.
- Before the v4 build, free space read 50.32 GiB. After all builds and packaging, `delivery-proof capacity --after` read 51.53 GiB; the 20 GiB reserve remains satisfied.
