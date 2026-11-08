# 3F Browser install and rollback retention — 2026-11-08 KST

- Installed current build: `/Users/rogan/Applications/3F Browser.app`, build 20, executable SHA-256 `72a9e93654a48e27fb17d8516fafe00017ff691c2a5c0bf7ca28f79c3bc300c3`; code signature and local launch verification passed.
- Kept one rollback: `/Users/rogan/Applications/3F Browser.rollback-0.1.0-20.app` (previous installed build 20, executable SHA-256 `dff7c101c2f57b4d5f8bc0e9b8049fb3c982531992d7e313b978553daf2fe188`; strict signature verification passed).
- Removed five older 3F rollback bundles after confirming their executables had no open file handles and no matching app-ownership records: build 18, +17, +16, +9, and +8. Their combined logical size was 18,180 KiB. `df -Pk` showed 60,847,608 KiB available before and 60,857,952 KiB after this removal (10,344 KiB increase).
- Removed the task-generated duplicate candidate directory `.build/installed-candidate-20261108` after installing and verifying the same executable. Its logical size was 4,160 KiB; the immediate free-space reading changed from 60,820,568 to 60,820,556 KiB, so no net reclaimed space is claimed for that step.
- The separate running QA candidate at `.build/qa-release-authorized-shortcut-20261101` (PID 71648) was not touched. User data, source, and active worktrees were not deleted.
