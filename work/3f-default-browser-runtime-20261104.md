# 3F default-browser handler verification — 2026-11-04

- Source commit: `2dd0c4f` (`fix(3f): resolve default browser by bundle path`).
- Change: status now requires Launch Services to resolve both HTTP and HTTPS to the exact current app bundle path. When it resolves to another 3F copy with the same bundle ID, the settings state reports that condition instead of claiming success.
- Focused verification: `swift test --filter DefaultBrowserServiceTests` passed 3/3; `git diff --check` passed before commit.
- Live Launch Services check: both schemes still resolve to `.build/install-candidate-20261031/3F Browser.app` (0.1.0+2), while the installed copy is `/Users/rogan/Applications/3F Browser.app` (0.1.0+9). `NSWorkspace.setDefaultApplication` and `lsregister -f` for the installed copy did not change the readback. The 0.1.0+2 instance PID 9559 is still running, so it was not unregistered or interrupted.
- Existing app-ownership records identify this same candidate path as a preserved 3F QA instance owned by task `focusfence-3fbrowser-fivehour-20261101` (thread `01a1948a-f39c-77b3-aa5e-030d44b9d966`). The candidate remains untouched.
- No external URL was opened, and no app was installed or relaunched. Runtime settings UI readback remains pending because the service fix is source-only.
- Build retention: reused SwiftPM `.build` outputs for the focused test; no separate app bundle or superseded version was created. Preserved the existing 2.1 GiB CEF SDK/build tree because it is needed for the open CEF integration work. No cleanup performed.
- Capacity: before test build 44.46 GiB free; after test build 43.75 GiB free, exceeding the 20 GiB reserve.

## Follow-up readback — 2026-11-05

- The Nov 4 stale-candidate observation above is historical. A fresh `NSWorkspace.urlForApplication(toOpen:)` read on Nov 5 resolved both `http` and `https` to `/Users/rogan/Applications/3F Browser.app` (installed `0.1.0+9`). `pgrep -x "3F Browser"` found no running 3F process at that check.
- No external URL was opened and the installed app was not launched. The current handler-path lookup is verified; visible Settings UI and a real external-link handoff remain unverified without a directly verified isolated AI-only UI route.
