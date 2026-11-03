# TODO

## Disabled integrations

- [ ] Verify the local Focus Fence policy service contract and re-enable navigation enforcement and search-result filtering in 3F. Until then, browsing works without Focus Fence enforcement.
- [x] Verify Focus Fence YouTube usage ingestion and quota behavior from 3F before enabling reporting or quota blocking; 3F now allows YouTube pages and enables the quota-aware playback reporter while Firefox browser-plugin work remains incomplete. Runtime receipt: `work/threef-youtube-playback-gate-20261104.md`.
- [ ] Re-enable the matching YouTube protection in Firefox only after all Focus Fence browser plugins pass their acceptance checks.
- [ ] Verify YouTube preview blocking in the installed 3F runtime before enabling its injected script.
- [ ] **3F default-browser runtime acceptance**: HTTP/HTTPS scheme declarations are already present in `Resources/Info.plist`; `BrowserSettingsView` displays handler status and exposes a user-triggered “3F를 기본 브라우저로 설정” action; `DefaultBrowserService` uses `NSWorkspace` to request both scheme handlers; `ThreeFBrowserApp` routes incoming URLs through `ThreeFURLRouter`. Source is committed (`3b06692`, external URL delivery follow-up `dfb5c0a`). Still verify the installed app reports both handlers after the user chooses the action and that an external HTTP/HTTPS link opens in 3F. No system default was changed during this source/tracker update.
