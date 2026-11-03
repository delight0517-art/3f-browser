# 3F QA candidate retention — 2026-11-01 20:09 KST

- Current Release candidate: `.build/qa-release-external-links-20261101/3F Browser.app`; isolated bundle ID `com.rogan.threef.browser.qa.externallinks20261101`; executable SHA-256 `7f5aed848f3c112f6e421ce575b6d464b743146bdad5c37f7c9206c0d21ff662`.
- `codesign --verify --deep --strict` and `workflow-control verify-mac` passed (`launchAllowed=true`, `local_dev`). The candidate is not installed or running; `lsof` found no open executable reference.
- Prior candidate `.build/qa-release-authorized-shortcut-20261101/3F Browser.app` remains the one rollback candidate. No outputs removed; peer-owned installed production 3F app was not changed.
- Focused and full source test evidence is in `work/3f-source-verification-20261101-2009.md`.
- Capacity after the isolated runtime harness compile/cleanup: 27.87 GiB free, above the required 20 GiB reserve. Temporary verification files were removed by Python's `TemporaryDirectory` context; no candidate process remained.
