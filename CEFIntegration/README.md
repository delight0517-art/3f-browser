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

## CEF auth-sidecar experiment (not the product architecture)

The earlier `CEFBrowserRuntime` prototype kept SwiftUI + WKWebView as the 3F
browser and launched a separate CEF app for Google authentication. That is not
the requested end state and must not be treated as Google-compliant: CEF is an
embeddable browser framework under the integrating app's control. Even a
standalone top-level CEF window that renders Google Accounts is only a probe; it
does not establish that Google accepts 3F as a full browser.

The requested architecture is a complete standalone 3F browser product whose
primary engine owns normal browsing and Google OAuth in the same browser UI.
The browser must expose the requested/current URI and secure-connection details,
preserve existing 3F features, and integrate the Focus Fence administrator
policy plugin. A browser-control sidecar may coordinate Only Chat, but it must
not replace the browser surface or move OAuth into an embedded user agent.

Google's policy is explicit that a developer must not direct OAuth to an
embedded user agent under its control. Do not spoof a browser user agent or copy
cookies between engines. A real OAuth login/callback in the 3F-owned standalone
browser is required before claiming compatibility. See
[`3F_BROWSER_MIGRATION_MATRIX.md`](3F_BROWSER_MIGRATION_MATRIX.md) for the full
feature and runtime acceptance criteria.

The CEF auth-only code, package helper, and profile are retained as diagnostic
history while the standalone browser migration proceeds. Do not install or
promote that helper as the 3F browser.

For a one-off startup trace, set `THREEF_CEF_STARTUP_TRACE=1` during build,
then launch the candidate executable with the same variable set. It writes only
startup milestones to stderr and is disabled by default.

## CEF Views browser-shell prototype (embedded-framework probe)

`build-3f-browser-shell.sh` builds a separate CEF Views app from the previously
rendering `cefsimple` sample, adding Back, Forward, Reload and a URL-only
address field. `package-3f-browser-shell-candidate.sh` prepares a signed
local preview that retains CEF sample app/helper identifiers for cross-process
rendezvous, and a separate per-candidate profile. It is not the final 3F
product bundle identity. It opens to
`about:blank`; it does not reuse or migrate the installed 3F profile.

This is still a prototype, not the 3F product shell or accepted OAuth runtime.
It has no tab strip, Only Chat/AI Mod connection, Focus Fence integration,
download and permission
handling, external-link routing, or product diagnostics. The address field
does not convert search phrases into Google searches, but destination
allowlisting is not implemented. Google OAuth compatibility is unverified;
do not install this candidate or make it the default browser.

## Legacy 3F authentication-only navigation policy

The legacy bundled `3F Chromium Browser.app` was launched for the originating
3F site and Google authentication. `patches/0005-3f-auth-only-navigation.patch` applies a
CEF navigation policy at main-frame/subframe navigation, popup creation, and
resource-request hooks. Page navigation is limited to the exact source origin
passed by 3F plus `accounts.google.com` and `consent.google.com`; non-HTTP(S),
other sites, YouTube/media hosts, and Google search endpoints are rejected.
The same policy checks address-bar navigation, redirects, links, and popups.
Ordinary non-YouTube page resources can still load from third-party origins;
this is a destination restriction, not a network-wide domain allowlist.

The policy is built into the restricted helper mode only. It has not been
verified with an actual Google sign-in and is not the target architecture.
The installed 3F app still uses WKWebView; the standalone full-browser product
candidate has not been integrated.

## 2026-11-12 CEF Views runtime diagnosis

The shell candidate package now retains CEF's original `org.cef.cefsimple`
application/helper identifiers. A prior package that rewrote those identifiers
failed CEF's Mach rendezvous lookup, so identifier rewriting is not used by this
probe. This sample identifier is only for local diagnosis; it is not the final
3F product identity or an installable product bundle.

The candidate toolbar now gives the toolbar, address field and buttons bounded
preferred sizes, places the browser view below the toolbar, and uses a fresh
profile for each diagnostic candidate. The CEF target compiles and the v4
preview passes deep/strict signature verification and `workflow-control
verify-mac`. Environment-gated startup trace messages are written to stderr
only when `THREEF_CEF_STARTUP_TRACE` is set.

The v4 trace reaches `OnContextInitialized`, `CreateTopLevelWindow`,
`OnWindowCreated`, toolbar layout and `window->Show()`. The process was gone
within three seconds; no persistent visible window or `CEF_LOAD_END` page-load
callback was confirmed. Earlier direct-launch output reported CEF helper Mach
rendezvous lookup failures. This remains a CEF Views sample-host/runtime issue,
not a verified 3F integration. The installed build20 and both Nov 8 rollback
backups remain untouched. Do not install or register these candidates as the
system browser.

The diagnostic packager leaves CEF's `CFBundleName` and `CFBundleDisplayName`
unchanged along with the app/helper identifiers. Renaming only the outer product
name is not enough evidence of a valid product bundle; the final 3F bundle must
keep CEF helper naming, paths and runtime identity consistent.

The v6/v7 trace also failed when launched from the original CEF build bundle,
so the earlier package-copy hypothesis does not explain the current exit. It
reaches `createApplication` but no longer returns from loading the sample
`MainMenu` nib. No stable window or page load has been verified. Stop using this
`cefsimple` toolbar prototype as the product migration path until that sample
lifecycle issue is resolved; the product itself remains on WKWebView.
