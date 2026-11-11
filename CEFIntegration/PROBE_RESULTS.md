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

## Full-browser migration candidate mode — 2026-11-11

- `build-cefclient-probe.sh` now accepts `THREEF_CEF_NAVIGATION_MODE=full-browser`
  to remove the auth-only navigation patch before compiling the CEF Views shell.
  The default `restricted-auth` mode retains the existing restricted-helper
  behavior.
- `package-3f-browser-candidate.sh` packages the full-navigation shell as a
  separate preview app with the 3F icon and a distinct preview bundle ID. It
  refuses to overwrite an existing preview.
- This is only a migration candidate route. The SwiftUI app still uses
  WKWebView, the preview does not yet receive external URL callbacks, and the
  Only Chat/AI Mod, Focus Fence, browser-session, downloads, permissions, and
  diagnostics features have not been integrated into CEF. No Google login or
  policy acceptance is claimed.
- The full-navigation CEF build and bundle packaging completed. Deep/strict
  signature checks and `workflow-control verify-mac` passed for the preview.
  Its main executable SHA-256 is
  `78a0f441dcb37090e15a7faea3439c3f3617e61900af13821cc2df137c686e17`.
- The preview did not remain running: two SpaceO launches exited before a
  browser window, including a second bundle with helper IDs aligned to the new
  parent ID. A physical `open --args` attempt and direct executable attempt
  also ended without a persistent process; direct launch printed only the CEF
  Views configuration notices and returned 0. No crash report was found. The
  UI/runtime blocker is unresolved, so general navigation, Google sign-in, and
  product integration remain unverified. The installed SwiftUI 3F app was not
  changed.
- A follow-up candidate added opt-in `[3FTRACE]` stderr milestones around CEF
  initialization, AppKit loop entry, `createApplication`, and
  `CreateRootWindow`. The build and candidate signature passed, and
  `workflow-control verify-mac` allowed local launch. A local `data:` launch
  recorded successful CEF initialization, queued and entered
  `createApplication`, and returned from `CreateRootWindow`; its captured trace
  stopped before the message-loop return marker. No browser window or retained
  process was confirmed, and a fresh 10-minute unified-log query contained no
  cefclient termination details. The trace is preserved at
  `work/3f-cef-startup-trace-20261111.log`; candidate executable SHA-256 is
  `bfc4511d0212bca142afede1d2ca0ed4353343acb98e05a0d674b19433ed1424`. This
  narrows the failure to after the root-window request but does not identify
  why the process disappears or prove CEF browser content was created.
- The trace build script now detects an already-patched source by the trace
  function itself. This avoids relying on `patch --dry-run -R`, which on this
  host reported a reverse-patch prompt as success even when the trace was not
  present. The first uninstrumented trace-named package was confirmed unused
  (no process or open files) and retired; the correctly instrumented candidate
  remains preserved for review.

## Build evidence

- Bundle: `.build/cef-156-arm64/cefsimple-isolated-build/tests/cefsimple/Release/cefsimple.app`
- Main executable SHA-256: `26eb7181f45df43d8d3a675d351922de4727c8cba91dd5705518a3d636512fb2`
- Build procedure: `CEFIntegration/build-isolated-probe.sh`
- The source patch is pinned under `CEFIntegration/patches/` and sets the CEF
  root profile before initialization. The downloaded CEF distribution and
  generated build remain in the ignored `.build` tree as active probe inputs.

## CEF Views browser-shell prototype — 2026-11-11

- Added `build-3f-browser-shell.sh`, a pinned `cefsimple` Views patch, and an
  isolated candidate packager. The prototype has Back/Forward/Reload and a URL
  field, starts at `about:blank`, rejects search phrases, and uses a dedicated
  `Browser Shell Candidate/User Data` profile.
- The CEF C++/Objective-C++ target compiled after correcting two compiler
  findings. The packaged candidate passed `codesign --verify --deep --strict`
  and `workflow-control verify-mac` (`launchAllowed: true`, `local_dev`). Main
  executable SHA-256:
  `9aa84e02cbb370cf3c3ed9386f50fca0ad7b7ee75f1304c712c231dcf3b8438b`.
- One physical-screen LaunchServices attempt returned without a retained
  `cefsimple` process or visible window. A targeted recent unified-log and
  crash-report query found no matching failure details. Do not repeat this
  launch route without new evidence.
- The candidate is not installed and does not replace the current SwiftUI /
  WKWebView 3F. Tabs, Only Chat/AI Mod, Focus Fence, downloads, permissions,
  destination allowlisting, product diagnostics, Google sign-in and Google
  policy acceptance remain unimplemented or unverified. The installed build20
  and the Nov 8 rollback backups remain untouched.

## CEF Views toolbar and startup diagnosis — 2026-11-12

- The packaged candidate preserves CEF's original `org.cef.cefsimple` app and
  helper identifiers. Rewriting them in an earlier package produced
  `MachPortRendezvousServer` lookup failures; the current package script no
  longer rewrites app/helper identifiers. The sample identifier is temporary
  diagnostic scaffolding and is not the final 3F app identity.
- Corrected the Views layout after inspecting the prior candidate: the window
  delegate had returned 800×600 as the preferred size for every child, which
  made the toolbar request the full window. The revised shell uses a 40-point
  toolbar, a flexible address field, bounded buttons, and places the browser
  view beneath the toolbar.
- The CEF Views target compiled and the packaged v4 preview passed
  `codesign --verify --deep --strict` and `workflow-control verify-mac`
  (`launchAllowed: true`, `local_dev`). The v4 startup trace is preserved at
  `work/3f-cefsimple-v4.stderr.log`.
- The v4 trace reached `OnContextInitialized`, `CreateTopLevelWindow`,
  `OnWindowCreated`, `toolbar layout complete`, and `window Show called`. The
  process was absent by the three-second readback. No persistent window,
  `CEF_LOAD_END`, or successful page render was confirmed. Earlier v3 direct
  launch evidence at `work/3f-cefsimple-v3-direct-trace.stderr.log` shows CEF
  initialization and message-loop entry followed by helper Mach rendezvous
  lookup failures. This does not establish why the sample process exits.
- The v4 app is diagnostic only, uses the fresh isolated profile
  `~/Library/Application Support/3F Browser/CEF/Browser Shell Candidate
  20261112 v4/User Data`, and was not installed. Installed 3F build20 and the
  Nov 8 backups remain unchanged. The SwiftUI/WKWebView product, Google login,
  tabs/session migration, Only Chat/AI Mod, Focus Fence, downloads, permissions,
  external URL ingress, and privacy-safe event logs remain incomplete or
  unverified.
- Later callback tracing narrowed the sample failure further. The v6 run reached
  `createApplication entered` but did not emit `MainMenu nib loaded`; its process
  was gone on the next read. The v7 run used the original CEF build bundle
  rather than a copied/renamed preview and showed the same trace cutoff. Logs:
  `work/3f-cefsimple-v6.stderr.log` and
  `work/3f-cefsimple-source-v7.stderr.log`. This means the package-copy or
  bundle-name change alone does not explain the current failure. No exception,
  crash report, visible persistent window, or `CEF_LOAD_END` was captured.
  Stop repeating this sample launch route and move integration work to the
  product's actual browser engine boundary.

## Restricted CEF product packaging guard — 2026-11-12

- `package-3f-browser-candidate.sh` now refuses a CEF tree unless the 3F
  navigation policy is compiled into main-frame navigation, popup creation,
  and resource-load hooks. Unrestricted `full-browser` builds remain engine
  probes and cannot be packaged as a 3F candidate.
- The package guard preserves the current user requirement to keep 3F
  navigation scoped to its configured site origin and Google authentication,
  while rejecting YouTube and Google Search routes. Trusted site-origin
  delivery and Focus Fence/Only Chat integration are still required.
- `bash -n`, the required policy-marker checks, and `git diff --check` passed.
  Packaging against restricted and unrestricted build trees was not run; no
  candidate was launched or installed in this slice.


## Restricted CEF Views runtime readback — 2026-11-12

- Launched the original CEF `cefclient.app` executable directly with the restricted-auth policy and an isolated `.build/3f-cef-restricted-profile-20261112` profile. The process stayed alive with CEF helper processes and created a visible Views browser window (window 842, 800×632) showing `https://example.com`. Screenshot: `work/3f-cefclient-restricted-source-20261112.png`; startup/runtime log: `work/3f-cefclient-restricted-source-20261112.stderr.log`. This is evidence for the upstream CEF Views sample only, not the installed 3F product.
- An attempted address-bar YouTube navigation was not proven: the captured window still showed `example.com`, but no policy-denial event or reliable input acknowledgement was captured. Do not count this as a verified navigation block.
- The separate renamed/repackaged preview did not remain running after its LaunchServices attempt. Cause is not established. The original sample's direct launch proves a visible CEF shell can run on this Mac, but product bundle identity/helper integration, 3F origin handoff, tabs/session, Focus Fence, downloads/permissions, Only Chat/AI Mod, diagnostics, Google sign-in and Google policy acceptance remain incomplete or unverified.
- The task-owned sample process was terminated with SIGTERM after Apple-event and ⌘Q quit requests did not close it. Its isolated profile had no open files and was removed. Installed build20 and the Nov 8 rollback backups remain untouched.


## CEF app/helper identity diagnosis — 2026-11-12

- Commit bb5c8eb removes post-build bundle-ID rewriting from the restricted candidate packager. With the original org.cef.cefclient app/helper IDs preserved, the signed packaged copy stayed alive and rendered Example Domain in visible window 905. Screenshot: work/3f-cef-preview-packager-identity-20261112.png; run log: work/3f-cef-preview-packager-identity-20261112.stderr.log.
- A candidate whose app and helper IDs were rewritten after linking to com.rogan.threef.browser.cefpreview exited. Its helper attempted bootstrap_look_up com.rogan.threef.browser.cefpreview.MachPortRendezvousServer.1 and received Unknown service name.
- Added a diagnostic build-time ID template patch in commit 1efee97. The built main app and helper Info.plists both used the custom ID, and deep/strict signing plus verify-mac passed. The executable SHA-256 was f823997e55bdfce40ff0857da4d17670546d0e08e8400eae4f9008466a08e1ba.
- The build-time custom-ID candidate still failed. With THREEF_CEF_STARTUP_TRACE=1 in the runtime environment, the main process reached CreateRootWindow and returned; helpers then failed the same custom-ID Mach rendezvous lookup. Evidence: work/3f-cef-preview-product-id-traced-env-20261112.stderr.log. The process produced no persistent window. A focused unified-log and crash-report query returned no additional records.
- This separates the working original-ID CEF sample from the custom product-ID startup failure. Do not treat matching Info.plist IDs or a valid ad-hoc signature as runtime acceptance. The CEF product identity/helper handshake remains unresolved. No installed 3F app, profile, or rollback backup changed.
- No Google sign-in or address-bar navigation-denial result was obtained. YouTube/Google Search blocking, local diagnostics durability, product integration, and Only Chat/AI Mod remain unverified.

## Standalone CEF Google sign-in surface probe — 2026-11-12

- The signed, identity-preserving upstream `org.cef.cefclient` candidate was launched on the Mac's physical screen with a fresh isolated profile and `https://accounts.google.com` as its initial page. Accessibility readback showed the window title `Sign in - Google Accounts` and browser controls for Back, Forward, Reload, View site information, and an Address and search bar. No credentials were entered.
- This is a positive control that the upstream CEF browser shell can display Google's sign-in entry page without an immediate `disallowed_useragent` response. It does not prove authentication, Google's policy acceptance of a 3F product build, or that a custom 3F bundle identity works.
- The CEF process was normally quit; process and profile-open-file checks were clear, and the isolated profile was removed. The installed 3F build20 and both rollback copies were not changed.
- The test remains a separate CEF sample process. Main-window ownership, 3F bundle/helper identity, navigation policy, Focus Fence, existing 3F feature parity, diagnostics, and Only Chat/AI Mod integration are still required before any replacement.
