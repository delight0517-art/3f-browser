# CEF macOS integration probe

This is a reproducible, isolated-profile probe for the 3F Chromium host decision.
CEF defaults to `~/Library/Application Support/CEF/User Data`, which is shared by
unrelated CEF applications. The patch in `patches/` assigns a 3F-specific
`root_cache_path` and `Default` profile before CEF initialization.

CEF Chrome runtime style uses the Chrome UI layer and supports the full browser
functionality exposed by CEF. On macOS it cannot be hosted as a Chrome-style
browser inside a native parent window; use CEF Views to own the browser's
top-level window. This probe does not claim compatibility with every Chrome Web
Store extension. Compatibility needs extension-by-extension verification.

Run `CEFIntegration/build-isolated-probe.sh` after placing the official CEF 156
arm64 binary distribution at the documented ignored `.build` path. It applies
the profile patch and builds/signs a separate `cefsimple-isolated-build` app
bundle, leaving any already-running sample bundle untouched. Verify the bundle
with `workflow-control verify-mac` before launching it, then use
`--url=data:text/html,...` or a test HTTPS URL. Do not reuse a profile while
another CEF process has it open. Do not change an installed 3F app from this
probe; validate rendering, clean quit, profile path, and extension install
behavior first.

## Modular update boundary

The product's current `HotModuleStore` accepts SHA-256-verified JSON and CSS
files in a staged revision with one rollback revision. This supports data and
style updates only; modules are not executable Swift or JavaScript, and the
current UI does not yet hot-mount arbitrary modules. A consumer must explicitly
reload an adopted JSON/CSS file. Browser engine, native UI logic, extension
integration, and CEF framework changes require a new product build and restart.
Do not label the current mechanism as a general-purpose hot-reload/plugin
system.

The probe script corrects the CEF sample's malformed framework copy before
signing. It also applies `patches/0002-log-load-callbacks.patch` so navigation
status and URL can be verified from `OnLoadEnd`. The isolated test confirmed
HTTPS rendering for example.com after that correction. The Chrome extension
manager and Chrome Web Store category page both rendered. No Web Store
extension has been installed or tested; compatibility remains unverified. See
`PROBE_RESULTS.md` for evidence and remaining product integration work.

## Browser-shell integration reconnaissance

The same isolated CMake build also contains the upstream `cefclient` target,
which has a Chromium-style address/search bar and internal extension manager.
`patches/0003-cefclient-profile.patch` gives it a private CEF root/cache path
before initialization. Run `CEFIntegration/build-cefclient-probe.sh` to apply
the patch, build `cefclient` with the existing
`.build/cef-156-arm64/cefsimple-isolated-build` directory, repair the generated
framework's `Versions/A` payload layout, and sign the helper apps before local
launch. The script prepares the candidate but does not launch it.

This reconnaissance verified an `example.com` page and
`chrome://extensions/` in the separately built and signed cefclient candidate.
It is not the 3F product bundle and must not be treated as product integration.
The current product still uses WKWebView; importing the upstream browser shell,
its lifecycle, profile migration, Only Chat control channel, and extension
install/update policy remain implementation work. No extension was installed.

## Full-browser product candidate

The current SwiftUI product still uses WKWebView. A packaged Chromium helper
does not replace that architecture and is not a complete answer to the Google
OAuth problem. `package-3f-browser-candidate.sh` prepares a separate, signed CEF
Views browser candidate from the existing `cefclient` shell. The candidate is
an independent top-level browser app with an address bar and general web
navigation, using the isolated 3F profile configured by
`0003-cefclient-profile.patch`.

Build the CEF shell in full-browser mode before packaging it:

```sh
THREEF_CEF_NAVIGATION_MODE=full-browser CEFIntegration/build-cefclient-probe.sh
CEFIntegration/package-3f-browser-candidate.sh
```

For a one-off startup trace, set `THREEF_CEF_STARTUP_TRACE=1` during build,
then launch the candidate executable with the same variable set. It writes only
startup milestones to stderr; capture that stream locally when diagnosing a
candidate. It does not record page URLs, page content, or credentials, and it
is disabled by default.

The existing auth-only helper remains available through the default
`restricted-auth` build mode and `package-3f-cef-host.sh`. Full-browser mode
removes the auth-only navigation patch from the generated CEF source before
compiling; it does not alter the Swift product's navigation controls. The
preview bundle has a separate identifier and is not installed as the current
3F Browser or registered as the system default. It is a migration candidate,
not proof of Google acceptance.

The next integration work must make this CEF Views engine the actual 3F browser
surface and migrate the existing tab/session behavior, downloads, permissions,
Focus Fence controls, Only Chat/AI Mod, external URL delivery, and local
privacy-safe diagnostics. Keep the current SwiftUI app and its user profile
available until those features and the browser runtime have been verified in
the replacement.

## 3F authentication-only navigation policy

The bundled `3F Chromium Browser.app` is launched for the originating 3F site
and Google authentication. `patches/0005-3f-auth-only-navigation.patch` applies a
CEF navigation policy at main-frame/subframe navigation, popup creation, and
resource-request hooks. Page navigation is limited to the exact source origin
passed by 3F plus `accounts.google.com` and `consent.google.com`; non-HTTP(S),
other sites, YouTube/media hosts, and Google search endpoints are rejected.
The same policy checks address-bar navigation, redirects, links, and popups.
Ordinary non-YouTube page resources can still load from third-party origins;
this is a destination restriction, not a network-wide domain allowlist.

The policy is built into the restricted helper mode only. It has not been
verified with an actual Google sign-in, so authentication compatibility and
Google's policy acceptance remain unconfirmed. The main 3F UI still uses
WKWebView until the full-browser product candidate is integrated.
