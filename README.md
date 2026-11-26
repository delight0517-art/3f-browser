# 3F Browser + Focus Fence Suite (macOS)

**3F Browser**는 **Focus Fence(FF)** 와 함께 동작하는 집중·생산성 중심의 macOS 네이티브 웹 브라우저입니다.  
**3F Browser** is a native macOS browser built to work seamlessly with **Focus Fence (FF)** for distraction-free focus, built-in Google Sign-In, and BlueCloud rule syncing.

## Direct Downloads (macOS)

- **[Focus Fence for macOS v1.0.7+2026112602 (Direct ZIP)](https://github.com/delight0517-art/3f-browser/releases/download/mac-focus-fence-v1.0.7%2B2026112602/FocusFence-macOS-v1.0.7%2B2026112602.zip)** — Native macOS Focus Fence app with in-app one-click 3F Browser download/install, 3F-only other-browser blocking, and `install.command` / `uninstall.command`.
  - Release notes & checksum (`SHA-256: 25b28eb48483ea6fac1f6894f6dc321d70549e0a360ae96369f1dbc80c37a3b7`): [mac-focus-fence-v1.0.7+2026112602](https://github.com/delight0517-art/3f-browser/releases/tag/mac-focus-fence-v1.0.7%2B2026112602)
- **[3F Browser for macOS (Latest ZIP)](https://github.com/delight0517-art/3f-browser/releases/latest/download/3F-Browser-macOS.zip)** — Standalone 3F Browser package ([All Releases](https://github.com/delight0517-art/3f-browser/releases)).
- **[Discord Community & Feedback](https://discord.gg/Ks78BjAhKK)** — Korean & English release notes, ideas, and bug reports.

---

## 주요 기능 / Features

- **Focus Fence 앱 내 3F Browser 원클릭 다운로드 & 설치**: Focus Fence (`v1.0.7+2026112602`) 설정 화면에서 3F Browser 최신 버전을 바로 다운로드·설치하고 기본 브라우저로 전환할 수 있습니다.
- **3F 전용 다른 브라우저 차단 모드 (3F-Only Mode)**: 3F Browser가 설치된 상태에서 Safari, Chrome, Edge, Arc, Brave, Firefox, Whale 등 다른 브라우저 실행 및 URL 접근을 자동 차단합니다 (3F 미설치 시 잠금 방지 안전장치 포함).
- **Google Sign-In & 서드파티 OAuth 지원**: `accounts.google.com` 및 OAuth 팝업이 Safari User-Agent와 `window.opener` 연결을 유지한 채 3F Browser 내부에서 직접 동작합니다.
- **BlueCloud 로그인 및 규칙 동기화**: `WildcardBlockStore`를 통해 BlueCloud 계정 로그인 및 차단 규칙 동기화를 지원합니다.
- **Focus Fence 연동 & 원클릭 기본 브라우저 전환**: 차단된 기본 브라우저 알림 또는 배너의 **메인 브라우저 바꾸기**를 누르면 Focus Fence가 3F Browser를 기본(`http`/`https`) 브라우저로 전환해 줍니다.
- **동의 기반 브라우저 보호 (Consent-Based Blocking)**: 설치 스크립트(`install.command`) 실행 시 사용자 명시적 동의(`[y/N]`)를 받은 뒤 Focus Fence 브라우저 차단을 활성화합니다.
- **간편 설치 / 제거 스크립트 포함**: 릴리스 압축 파일에 `install.command`와 `uninstall.command`가 함께 들어 있습니다.

---

## 설치 방법 / Installation

1. 상단 **Direct Downloads (macOS)** 또는 [Releases](https://github.com/delight0517-art/3f-browser/releases)에서 패키지를 다운로드합니다:
   - [`FocusFence-macOS-v1.0.7+2026112602.zip`](https://github.com/delight0517-art/3f-browser/releases/download/mac-focus-fence-v1.0.7%2B2026112602/FocusFence-macOS-v1.0.7%2B2026112602.zip) (Focus Fence + `install.command` / `uninstall.command` · 앱 내 3F Browser 원클릭 설치 지원)
   - [`3F-Browser-macOS.zip`](https://github.com/delight0517-art/3f-browser/releases/latest/download/3F-Browser-macOS.zip) (3F Browser 단독 + `install.command` / `uninstall.command`)
2. 압축을 푼 뒤 폴더 내 `install.command`를 더블클릭(또는 터미널에서 실행)합니다.
3. 안내에 따라 **기본 브라우저 변경** 및 **Focus Fence 브라우저 차단 실행 동의**를 선택합니다.

---

## 제거 방법 / Uninstall

- 포함 된 `uninstall.command`를 실행하면 `3F Browser.app`과 `Focus Fence.app`을 안전하게 종료·삭제하고, 선택적으로 로컬 앱 데이터(`Application Support`)까지 정리할 수 있습니다.

---

## 소스에서 빌드 / Build from Source

```bash
swift build -c release --product ThreeFBrowser
```

---

## 라이선스 / License

[MIT License](LICENSE)
