# 3F default browser current handler readback — 2026-11-05

## Current Launch Services result

Using the same public AppKit lookup as `DefaultBrowserService.refresh()`:

- `http` resolves to `/Users/rogan/appDev/apps/3f-browser-mac/.build/onlychat-sigterm-probe/3F Browser.app`.
- `https` resolves to the same path.
- That bundle ID is `com.rogan.threef.browser`, version `0.1.0`, build `2`.
- The installed app `/Users/rogan/Applications/3F Browser.app` has the same bundle ID, version `0.1.0`, build `9`.
- Neither the stale candidate nor the installed 3F app has a matching process at the time of this check.

The two schemes therefore resolve to the wrong copy of 3F. A deprecated Launch Services bundle-ID lookup was also observed during the investigation, but the exact path above comes from `NSWorkspace.urlForApplication(toOpen:)`, the same path-based API the app uses.

The supported `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` API was invoked for both schemes with the installed build9 path. Both calls returned without throwing, but a separate fresh `NSWorkspace.urlForApplication(toOpen:)` read still returned build2 for both. The one-off helper's later readback code had an interpolation error and crashed while forming its URL; this did not change the independent correct readback. Its Python `TemporaryDirectory` cleanup removed the helper source and binary automatically. A follow-up `/tmp` scan found no `starnet-verify-*` directory.

## Targeted Launch Services cleanup — 2026-11-05

The installed app itself was verified as `/Users/rogan/Applications/3F Browser.app`, bundle `com.rogan.threef.browser`, version `0.1.0+9`; `codesign --verify --deep --strict` passed and `workflow-control verify-mac` returned `launchAllowed=true`.

To stop Launch Services selecting same-bundle-ID development copies, only their registrations were removed; no candidate bundle or source was deleted. The exact deregistered paths were:

- `.build/onlychat-sigterm-probe/3F Browser.app` (`0.1.0+2`)
- `.build/window-attach-candidate-20261101/3F Browser.app` (`0.1.0+2`)
- `.build/window-attach-candidate2-20261101/3F Browser.app` (`0.1.0+2`)
- `.build/youtube-quota-runtime-20261104/3F Browser.app` (`0.1.0+10`)
- `.build/youtube-usage-bridge-candidate-20261104/3F Browser.app` (`0.1.0+9`)

After each unregister, fresh AppKit reads showed Launch Services advancing through the stale candidates. After the final unregister, a new process read back both `http` and `https` as `/Users/rogan/Applications/3F Browser.app`. This is exact handler-path evidence. Candidate files remain available and can be registered again with `lsregister -f '<candidate path>'` if needed. No app was launched, no settings UI was operated, and no external URL was opened; runtime UI delivery remains unverified.

## Scope and remaining work

Other ignored `.build/*/3F Browser.app` candidates remain on disk and some remain registered; the five exact registrations listed above were the successive handlers displaced by the cleanup. No candidate files were deleted. Both schemes now resolve to the installed build9 path, so the OS handler-path requirement is satisfied. The app settings UI and opening an external URL in the live app remain unverified because no isolated AI UI route was available; do not claim those runtime stages from the AppKit lookup alone.
