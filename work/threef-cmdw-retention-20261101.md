# 3F Browser Command-W slice — retention receipt (2026-11-01 KST)

- Canonical source: `/Users/rogan/appDev/apps/3f-browser-mac`, branch `main`, HEAD `5eaaee0b9b391a0fed88ac2cbf22ddc426ed0d43`. The focused Command-W mapping, event dispatch, selected-tab close handler, and keyboard test are present in the dirty checkout; earlier changes remain intact.
- Focused keyboard tests: 5/5 passed, including Command-W mapping and Shift-Command-W passthrough. Full Swift package suite: 28/28 passed.
- Release candidate: `.build/session-restore-candidate-20261101/3F Browser.app`, bundle `com.rogan.threef.browser`, build `2`, executable SHA-256 `5f189b00787137bd2d32d61279f970154c3ef75b5fe7f03d7203b452271b05e0`; strict codesign and `workflow-control verify-mac` passed. Candidate was built from the canonical dirty source and was not launched or installed.
- Storage: 2 GiB guarded peak; 47.59 GiB free before/after, preserving the 20 GiB reserve. Reused one task candidate path; did not remove any older output or user data.
- Installed 3F Browser PID 71862 and its active page were left untouched. Actual Command-W UI behavior remains unverified until a safe runtime session is available.
- This receipt records the candidate at the time the Command-W slice completed. A subsequent session-restore normalization build reused the same candidate path; the current bundle hash is recorded in `threef-session-restore-retention-20261101.md`.
