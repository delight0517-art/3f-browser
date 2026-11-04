# CEF 156 profile and rendering probe

Date: 2026-10-29 (Mac, arm64)

## Verified

- The official CEF 156 arm64 distribution builds as a separate app bundle with
  an app-specific CEF profile.
- The probe build script repairs the sample CMake framework-copy mistake:
  `COPY_MAC_FRAMEWORK` copies the framework root into `Versions/A`, introducing
  an invalid `Versions/A/A -> A` link. The script now copies the distribution's
  actual `Release/...framework` payload before creating the version links.
- The standalone nested-signature pass and final
  `codesign --verify --deep --strict` passed; `workflow-control verify-mac`
  reported `launchAllowed: true` in `local_dev` mode.
- A diagnostic `OnLoadEnd` callback recorded
  `main=1 status=200 url=https://example.com/` at
  `~/Library/Application Support/3F Browser/CEF/User Data/cef-load-callback.log`.
- After correcting the framework bundle layout, `https://example.com` rendered
  its visible Example Domain text. The earlier blank HTTPS rendering was
  therefore caused by the malformed copied framework layout in this probe.
- A `data:` HTML page rendered visible text in the CEF window.
- `chrome://extensions/` rendered the Chrome extension manager and its Chrome
  Web Store link. This demonstrates the Chrome runtime UI path, not successful
  installation of any extension.
- On 2026-11-05, the signed isolated `cefclient` candidate loaded the Focus Fence
  Chrome extension v1.3.71 as an unpacked extension in a disposable profile.
  `chrome://extensions/` showed it enabled, and `https://example.com/` rendered
  while it remained enabled. The CRX source SHA-256 was
  `30b8619df0f892a8e3eb0dbecb7ae1f69567e13110273aac214ee49b67c94e36`.
  The app was normally quit and the disposable profile removed. This proves
  extension load/render compatibility in the CEF probe only; it does not prove
  Focus Fence blocking behavior or 3F product integration.
- Following the Web Store link rendered the Chrome Web Store Extensions page
  and recommendation content. The page showed its "Switch to Chrome?" prompt;
  dismissing it revealed the store page. No extension was installed.
- CEF helper command lines and open files showed the new process using
  `~/Library/Application Support/3F Browser/CEF/User Data`, separate from the
  earlier CEF process using `~/Library/Application Support/CEF/User Data`.
- The isolated probe was normally quit from its app menu. Its process and
  profile file handles were absent afterward.

## Failed or unverified

- No Chrome Web Store install, packaged-CRX install, or Focus Fence block-rule
  behavior was tested. Universal extension compatibility is not established.
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
