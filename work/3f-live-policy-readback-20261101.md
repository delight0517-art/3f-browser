# 3F live Focus Fence readback — 2026-11-01

Read-only requests to the local Focus Fence service on `127.0.0.1:17361`:

- `GET /rules?browser=3f`: HTTP 200 with a structurally valid rules payload. The current YouTube policy says blocked.
- `GET /usage/youtube`: HTTP 200; current usage was 1,339 seconds against a 20-minute (1,200-second) daily cap, with `blocked=true`. A 3F row was absent from both `browserSeconds` and `browserUsageLastSeen`.
- `GET /usage/browser-protection`: HTTP 200. The 3F row reports `running=true`, `processMatchesPolicy=true`, `blockedByFallback=false`, `inAppNavigationPolicyConfigured=true`, `urlProtectionPath=in-app-navigation-policy`, and `inAppNavigationPolicyRuntimeVerified=false`. `usageCollectionAvailable=false` in the row.
- `OPTIONS /ingest` with YouTube Origin, requested POST, and `content-type`: HTTP 204 with `Access-Control-Allow-Origin: *`, allowed methods `GET, POST, OPTIONS`, and allowed header `Content-Type`. The live server's CORS preflight supports the 3F JSON report request.
- `lsof` confirms PID 14021 (the currently running Debug Focus Fence app) owns TCP ports 17361 and 17362. Its app status response omits the `inAppNavigationPolicyConnected` field present in current source, so its runtime may not include the latest source change.
- No 3F browser UI or control endpoint was used; the installed app remains owned by the active peer Only Chat task. Gemini/Drive content navigation, YouTube denial in WebKit, and usage ingestion remain unverified.
