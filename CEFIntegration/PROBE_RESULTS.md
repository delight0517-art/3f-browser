# CEF 156 profile and rendering probe

Date: 2026-10-29 (Mac, arm64)

## Verified

- The official CEF 156 arm64 distribution builds as a separate app bundle with
  an app-specific CEF profile.
- `codesign --verify --deep --strict` and `workflow-control verify-mac` passed;
  `launchAllowed` was true in `local_dev` mode.
- A `data:` HTML page rendered visible text in the CEF window.
- `chrome://extensions/` rendered the Chrome extension manager and its Chrome
  Web Store link. This demonstrates the Chrome runtime UI path, not successful
  installation of any extension.
- CEF helper command lines and open files showed the new process using
  `~/Library/Application Support/3F Browser/CEF/User Data`, separate from the
  earlier CEF process using `~/Library/Application Support/CEF/User Data`.
- The isolated probe was normally quit from its app menu. Its process and
  profile file handles were absent afterward.

## Failed or unverified

- A test `https://example.com` navigation appeared in the CEF accessibility
  state as `example.com/`, but the captured browser content remained blank.
- Clicking the Chrome Web Store link also resulted in a blank CEF page. A
  separate read-only `curl -I https://chromewebstore.google.com/` returned
  HTTP 200, so that alone does not identify the CEF rendering failure's cause.
- No Chrome Web Store extension was installed or tested. Universal extension
  compatibility is not established.
- The previous CEF process PID 26972 still owns handles in the shared default
  CEF profile. It was left untouched. The isolated profile is independent.
- The tested CEF app is a probe, not the installed 3F Browser product. Product
  integration, tabs/session migration, downloads, permissions, update lifecycle,
  and Only Chat runtime handoff remain outstanding.

## Build evidence

- Bundle: `.build/cef-156-arm64/cefsimple-isolated-build/tests/cefsimple/Release/cefsimple.app`
- Main executable SHA-256: `26eb7181f45df43d8d3a675d351922de4727c8cba91dd5705518a3d636512fb2`
- Build procedure: `CEFIntegration/build-isolated-probe.sh`
- The source patch is pinned under `CEFIntegration/patches/` and sets the CEF
  root profile before initialization. The downloaded CEF distribution and
  generated build remain in the ignored `.build` tree as active probe inputs.
