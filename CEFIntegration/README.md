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
