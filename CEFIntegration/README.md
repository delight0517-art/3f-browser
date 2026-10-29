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

See `PROBE_RESULTS.md` for observed outcomes and current failures. In particular,
the extension manager appeared, while HTTPS content and the Web Store page were
blank in the current local probe; do not treat those flows as working yet.
