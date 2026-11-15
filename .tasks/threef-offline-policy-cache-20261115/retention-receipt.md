# 3F offline policy build retention receipt — 2026-11-15

- Installed current output: `/Users/rogan/Applications/3F Browser.app`, build 0.1.0+35, executable SHA-256 `274e8ee8fab506be3c8c134d639ca7224dc8648e83a0c366e6522b2a6f880427`; strict signature and `verify-mac` passed; live Google search/readback passed.
- Preserved rollback: `/Users/rogan/Applications/3F Browser.rollback-v34-20261115.app`, the immediately preceding installed +34 bundle.
- Retired older rollback from Applications: `/Users/rogan/Applications/3F Browser.rollback-v33-20261115.app` moved to the user's Trash after replacement +35 passed install and runtime checks. `pgrep` and `lsof` showed no process using that v33 path. Trash move is reversible and does not claim disk-space recovery.
- Build candidate was moved from `.build/3f-offline-policy-cache-20261115/3F Browser.app` into the installed path; it is no longer a duplicate generated candidate. Reusable SwiftPM output `.build/release/ThreeFBrowser` remains in its shared build path.
- Post-build available space readback: 23.83 GiB; the small app rename/install and Trash move did not reclaim or consume material space.
- FF remained online; no outage simulation or disconnected runtime claim is included.
