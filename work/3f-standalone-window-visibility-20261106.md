# 3F Browser standalone window visibility — 2026-11-06 KST

## Diagnosis

- Only Chat's read-only `GET /api/browser/status` reported the 3F control service available but no open page.
- The authenticated 3F control endpoint returned `503 browser view not ready`. Only Chat's `ThreefBrowserBridge` treats that exact response as a reason to fall back to the `threef://open` URL.
- Before this change, `ThreeFURLRouter.receive` only queued the URL. It did not restore, activate, or open the standalone 3F Browser window. The control API also had no window-presentation callback before it reported navigation success.

## Change and verification

- `BrowserView` registers a shared window presenter. External 3F URLs restore and focus the existing standalone window, or request one `WindowGroup` window when none is present. Repeated fallback delivery does not request duplicate windows while one is opening.
- The authenticated control navigation path now requests the standalone window before navigating and keeps `browser view not ready` as the fallback when the view is unavailable.
- Focused check: `swift test --filter 'ThreeFBrowserControlTests|ThreeFURLRouterTests'` — 22 tests passed.
- Candidate package: `.build/onlychat-standalone-window-candidate-20261106/3F Browser.app`, version `0.1.0` build `17`, executable SHA-256 `45ce22e6e57434485d5bbd8811dd52295e91c088cd0bf34d885b9b2306accf7d`. `codesign --verify --deep --strict`, `plutil -lint`, and `workflow-control verify-mac` passed (`local_dev`, `launchAllowed=true`).

## Retention and remaining proof

- Candidate remains preserved and is not installed or launched. No prior candidate or source artifact was removed or overwritten; the existing 3F process and installed bundle were left untouched. `lsof` found no process using the candidate executable.
- Free space was 30.78 GiB before and after the build; 2 GiB was reserved for the operation with the required 20 GiB reserve.
- Installed-app and visible-window behavior remain unverified because no directly evidenced isolated macOS UI route is available. The running installed process and new candidate are separate artifacts.
