# 3F CEF candidate retention receipt — 2026-11-12 KST

- Canonical source: `/Users/rogan/appDev/apps/3f-browser-mac`, main branch.
- Reused build tree: `.build/cef-156-arm64/cefsimple-isolated-build`.
- Kept diagnostic bundles: `.build/3f-cefsimple-browser-shell-candidate` and v2 through v6 (about 330 MiB each). None has verified persistent-window/page-load runtime, so each remains an unverified evidence candidate; no superseded candidate was retired.
- Installed 3F Browser build20 and the two Nov 8 rollback backups were not changed.
- Exact process check: no `cefsimple` or CEF helper remained after the v4 launch; `lsof +D` found no open file under the v4 bundle.
- No user profile, session, or authentication data was deleted. Diagnostic CEF profiles are separate and preserved.
- The v5/v6/v7 rebuilds reused the same CEF build tree. The final `delivery-proof capacity --after` read was 51.37 GiB free; the 20 GiB reserve remains satisfied.

- Build20 rollback verified: bundle version 0.1.0 (20), deep/strict signature valid, executable SHA-256 `dff7c101c2f57b4d5f8bc0e9b8049fb3c982531992d7e313b978553daf2fe188`; installed build20 hash differs and was not modified. The Nov 8 09:53 backup remains within its 14-day window, expiring 2026-11-22 09:53:04 KST; retained.


## Restricted cefclient readback — 2026-11-12 01:01 KST

- Kept restricted-auth candidate .build/3f-cef-restricted-auth-candidate-20261112/3F Browser Preview.app for review; main executable SHA-256 190a2f1d54adde0fdd4fda0c41a7bf9a769e1decb8d683d9b45c9bbd9fff6f2f, deep/strict signature and local launch policy passed. Its LaunchServices launch did not remain running.
- Separately launched the original CEF source bundle directly. Its visible Views window rendered Example Domain; screenshot and stderr log are retained under work/3f-cefclient-restricted-source-20261112.*. This does not prove the renamed candidate or 3F product works. YouTube block was not verified.
- Closed task-owned CEF process after normal quit requests did not work; verified no process/helper or open profile files. Removed only the isolated example.com profile .build/3f-cef-restricted-profile-20261112. No installed app, user profile, session or rollback was changed.
- Installed build20 remains running as PID 706. The Nov 8 rollback remains inside the user-requested 14-day retention period through 2026-11-22 09:53 KST.


## Bundle identity and restricted-navigation follow-up — 2026-11-12 01:25 KST

- Commits bb5c8eb and 1efee97 followed by c57ee26 record the package identity change, build-time ID experiment, and runtime evidence.
- The original-ID packaged candidate remains as a working positive control; it rendered Example Domain. The build-time custom-ID candidate and startup-traced variant remain diagnostic-only because the helper cannot find the custom Mach rendezvous service and no window persists. The post-link-rewritten candidate remains separate failure evidence.
- The restricted-mode launch with youtube.com produced a visible CEF window with youtube.com in its address field and an empty page. No explicit deny event or reliable navigation callback was captured, so this is not conclusive policy-denial proof.
- Closed all task-owned CEF windows and verified no cefclient/helper processes. Removed only their isolated test profiles after no open files remained. Screenshots and stderr logs are retained under work/.
- Installed build20 remains running as PID 706; the rollback bundle created Nov 8 remains protected until Nov 22 09:53 KST. Neither the installed app nor either backup was modified.
