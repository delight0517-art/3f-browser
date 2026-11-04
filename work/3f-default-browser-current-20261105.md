# 3F default browser current handler readback — 2026-11-05

## Current Launch Services result

Using the same public AppKit lookup as `DefaultBrowserService.refresh()`:

- `http` resolves to `/Users/rogan/appDev/apps/3f-browser-mac/.build/onlychat-sigterm-probe/3F Browser.app`.
- `https` resolves to the same path.
- That bundle ID is `com.rogan.threef.browser`, version `0.1.0`, build `2`.
- The installed app `/Users/rogan/Applications/3F Browser.app` has the same bundle ID, version `0.1.0`, build `9`.
- Neither the stale candidate nor the installed 3F app has a matching process at the time of this check.

The two schemes therefore resolve to the wrong copy of 3F. A deprecated Launch Services bundle-ID lookup was also observed during the investigation, but the exact path above comes from `NSWorkspace.urlForApplication(toOpen:)`, the same path-based API the app uses.

## Scope and remaining work

There are many ignored `.build/*/3F Browser.app` candidates with the same bundle ID. They were not removed or unregistered because they are retained work artifacts and no ownership/reference audit was performed. No Launch Services mutation, app launch, default-browser prompt, or external URL open was performed in this check. CUA exposed an app inventory but did not prove a desktop isolated from the user's physical display, so the app's settings UI was not operated. The previously authorized default-browser task remains open until the installed app itself is selected through its supported path and both schemes are read back as `/Users/rogan/Applications/3F Browser.app`.
