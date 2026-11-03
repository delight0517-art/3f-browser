# 3F SIGTERM probe candidate retention receipt — 2026-10-31

- Candidate: `.build/onlychat-sigterm-probe/3F Browser.app`
- Purpose: isolated diagnostic candidate only; not installed and not user-profile data.
- Executable SHA-256: `85f9e7983c099d35090c4fa04e2918945c05a907fee74b932cac3dd5fbc37e7a`
- Bundle version/build: `0.1.0` / `2`; bundle ID `com.rogan.threef.browser`.
- Verification: `codesign --verify --deep --strict --verbose=2` passed; focused `ThreeFBrowserControlTests` 12/12 passed in saved test run.
- Retain while diagnosing why Focus Fence PID 5860 sent SIGTERM. Candidate is the only built diagnostic artifact; no install or runtime session depends on replacing it.
