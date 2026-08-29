# MonglePet Preview 다운로드 화면 전달 자료

## 목적과 적용 범위

이 문서는 `https://dev.mapleroom.kr/monglepet` 다운로드 화면 담당자가 Windows와 macOS Preview 정보를 그대로 반영할 수 있게 하는 전달 자료다. MonglePet 데스크톱 저장소에서는 GitHub Release와 배포 계약까지만 관리하며, 별도 서버의 소스 수정과 운영 배포는 이 문서의 범위가 아니다.

이 자료는 펫 공유 커뮤니티의 `.monglepet` 다운로드 계약과 별개다. 아래 링크는 MonglePet 데스크톱 앱만 제공한다.

별도 서버 저장소에 구현을 요청할 때는 [`PREVIEW_DOWNLOAD_SERVER_PROMPT.md`](PREVIEW_DOWNLOAD_SERVER_PROMPT.md)를 함께 전달한다.

## 다운로드 화면 권장 구성

- 페이지 상단에는 MonglePet Preview의 공통 소개를 두고 각 카드에 플랫폼별 최신 버전을 표시한다.
- 그 아래에 `Windows`와 `macOS` 다운로드 카드를 나란히 제공한다.
- 각 카드는 다른 플랫폼의 파일을 자동 선택하거나 강제로 내려받게 하지 않고 사용자가 직접 선택하게 한다.
- 두 카드 모두 지원 운영체제, 버전, 파일 크기, 서명 상태, SHA-256과 릴리스 정보 링크를 다운로드 버튼 가까이에 표시한다.
- macOS 카드는 일반 배포가 아닌 `제한된 테스터용`임을 제목 또는 상태 배지에서 바로 알 수 있게 한다.

## Windows 게시 원본

| 항목 | 값 |
| --- | --- |
| 제품 버전 | `1.4.0` |
| Windows 파일 버전 | `1.4.0.14` |
| 표시 이름 | `MonglePet Windows 1.4.0 Preview 2` |
| Git 태그 | `windows-v1.4.0-preview.2` |
| 기준 커밋 | `682acfa50b8a48ca6c2ce6531c4dd0be673ab082` |
| 게시일 | 2026-08-29 |
| 설치기 파일 | `MonglePet-Windows-1.4.0.14-x64-Setup.exe` |
| 설치기 크기 | 65,270,050 bytes (약 62.25 MiB) |
| 설치기 SHA-256 | `C1B8066BFF2BCB1840E594AF668A6E3EF0226FAB5590804594AF3A2E05D64678` |
| 서명 상태 | 미서명 Preview |
| 업데이트 방식 | 새 설치기를 내려받아 기존 설치 위에 수동 설치 |

- 릴리스 페이지: <https://github.com/saehajoo/MonglePet/releases/tag/windows-v1.4.0-preview.2>
- 설치기 직접 다운로드: <https://github.com/saehajoo/MonglePet/releases/download/windows-v1.4.0-preview.2/MonglePet-Windows-1.4.0.14-x64-Setup.exe>
- 체크섬 파일: <https://github.com/saehajoo/MonglePet/releases/download/windows-v1.4.0-preview.2/SHA256SUMS.txt>

웹사이트에서 GitHub 파일을 그대로 연결할 때는 위 버전 고정 URL을 사용한다. 자체 서버에 복제할 때는 파일명을 바꾸거나 다시 압축하지 말고, 업로드 후 공개 URL에서 내려받은 파일의 SHA-256을 다시 확인한다.

## macOS 게시 원본

| 항목 | 값 |
| --- | --- |
| 제품 버전 | `1.4.0` |
| macOS 빌드 번호 | `8` |
| 표시 이름 | `MonglePet macOS 1.4.0 Preview 1` |
| Git 태그 | `macos-v1.4.0-preview.1` |
| 기준 커밋 | `78ac0dfb52f0cb4e0d436649603c29dea91e652d` |
| 게시일 | 2026-08-27 |
| ZIP 파일 | `MonglePet-1.4.0-build.8-preview.zip` |
| ZIP 크기 | 8,833,960 bytes (약 8.42 MiB) |
| ZIP SHA-256 | `EBB3A12F0B829671399D44E1FD71AB16486E590F46AC1EC57F0C904AECF55820` |
| 서명·공증 상태 | Developer ID 미서명·Apple 미공증 Preview |
| 제공 범위 | 제한된 테스터용 |

- 릴리스 페이지: <https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.4.0-preview.1>
- ZIP 직접 다운로드: <https://github.com/saehajoo/MonglePet/releases/download/macos-v1.4.0-preview.1/MonglePet-1.4.0-build.8-preview.zip>
- 체크섬 파일: <https://github.com/saehajoo/MonglePet/releases/download/macos-v1.4.0-preview.1/MonglePet-1.4.0-build.8-preview.zip.sha256>
- 빌드 manifest: <https://github.com/saehajoo/MonglePet/releases/download/macos-v1.4.0-preview.1/MonglePet-1.4.0-build.8-preview.manifest.txt>

macOS ZIP도 GitHub의 버전 고정 URL을 원본으로 사용한다. 자체 서버에 복제한다면 ZIP을 다시 만들지 않고 공개 URL에서 다시 받은 파일의 크기와 SHA-256을 확인한다.

## Windows 사용자에게 표시할 필수 정보

- 지원 환경: Windows 11 25H2 build 26200 이상, x64
- 관리자 권한 없이 현재 사용자 영역에 설치됨
- 기존 `1.0.0.13` 설치 위에 설치 가능
- 설정과 펫 라이브러리는 `%LOCALAPPDATA%\MonglePet`에 보존됨
- 코드 서명과 자동 업데이트가 없는 Preview
- SmartScreen, Smart App Control 또는 조직 정책에서 경고하거나 차단할 수 있음
- 전역 보안 설정을 끄도록 안내하지 않음
- 공식 링크에서 받은 파일이며 SHA-256이 일치할 때만 사용자가 실행 여부를 판단하도록 안내

## macOS 사용자에게 표시할 필수 정보

- 지원 환경: macOS 14 이상, Apple Silicon 및 Intel Mac
- 일반 공개용이 아닌 제한된 테스터용 Preview
- Developer ID로 서명되지 않았고 Apple 공증을 받지 않음
- ZIP 해제 후 `MonglePet.app`을 응용 프로그램 폴더로 이동
- 첫 실행이 차단되면 `시스템 설정 → 개인정보 보호 및 보안`의 개별 앱 승인 경로만 안내
- Gatekeeper 전역 비활성화나 `xattr`을 통한 quarantine 제거를 안내하지 않음
- 공식 링크에서 받은 ZIP이며 SHA-256이 일치할 때만 사용자가 실행 여부를 판단하도록 안내

## 복사 가능한 Markdown 안내

```markdown
## MonglePet Windows 1.4.0 Preview 2

행동 중심 설정과 최종 몽글이 위에 펫 제작기 드래그·미리보기·독립 활성 인스턴스, 다크·라이트 설정 대비와 모든 이동 방식의 클릭 통과를 보완한 Windows Preview입니다.

[Windows용 설치기 다운로드](https://github.com/saehajoo/MonglePet/releases/download/windows-v1.4.0-preview.2/MonglePet-Windows-1.4.0.14-x64-Setup.exe)

- 지원 환경: Windows 11 25H2 build 26200 이상, x64
- 파일 크기: 약 62.25 MiB
- 버전: 1.4.0.14
- SHA-256: `C1B8066BFF2BCB1840E594AF668A6E3EF0226FAB5590804594AF3A2E05D64678`

현재 파일은 코드 서명되지 않은 Preview이므로 Windows SmartScreen 경고가 표시될 수 있습니다. 공식 GitHub Release에서 내려받았고 SHA-256이 위 값과 일치할 때만 실행 여부를 판단해 주세요. Smart App Control이나 조직 정책에서 차단되는 환경에서는 보안 설정을 끄지 말고 다음 서명 버전을 기다려 주세요.

기존 MonglePet이 설치되어 있다면 새 설치기를 그대로 실행해 업데이트할 수 있습니다. 기존 설정과 펫 라이브러리는 유지됩니다. 현재 Preview는 자동 업데이트를 제공하지 않습니다.

[릴리스 정보와 체크섬 보기](https://github.com/saehajoo/MonglePet/releases/tag/windows-v1.4.0-preview.2)
```

```markdown
## MonglePet macOS 1.4.0 Preview 1

행동 중심 자동 동작과 이동 방식별 독립 설정, 애니메이션 제작·복제 개선과 최종 기본 몽글이 1.0.3을 포함한 MonglePet macOS `1.4.0 (8)` 미서명·미공증 Preview입니다. 현재 파일은 제한된 테스터용으로 제공합니다.

[macOS용 Preview ZIP 다운로드](https://github.com/saehajoo/MonglePet/releases/download/macos-v1.4.0-preview.1/MonglePet-1.4.0-build.8-preview.zip)

- 지원 환경: macOS 14 이상, Apple Silicon 및 Intel Mac
- 파일 크기: 약 8.42 MiB
- 버전: 1.4.0 (8)
- SHA-256: `EBB3A12F0B829671399D44E1FD71AB16486E590F46AC1EC57F0C904AECF55820`

ZIP을 압축 해제하고 `MonglePet.app`을 응용 프로그램 폴더로 이동하세요. 이 빌드는 Developer ID로 서명되지 않았고 Apple 공증을 받지 않았으므로 최초 실행이 차단될 수 있습니다. 공식 GitHub Release에서 내려받았고 SHA-256이 위 값과 일치하는 경우에만 `시스템 설정 → 개인정보 보호 및 보안`에서 MonglePet의 개별 실행 허용 여부를 판단해 주세요. Gatekeeper를 끄거나 quarantine을 제거하지 마세요.

[릴리스 정보·체크섬·빌드 manifest 보기](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.4.0-preview.1)
```

## 복사 가능한 HTML 예시

기존 사이트의 디자인 시스템과 접근성 구성요소가 있다면 클래스명과 마크업 구조는 그 체계에 맞춘다. 아래 예시는 콘텐츠와 링크의 기준일 뿐이다.

```html
<section aria-labelledby="monglepet-windows-preview-title">
  <h2 id="monglepet-windows-preview-title">MonglePet Windows 1.4.0 Preview 2</h2>
  <p>
    펫 제작기 드래그·미리보기·독립 활성 인스턴스와 설정 대비,
    모든 이동 방식의 클릭 통과를 보완한 Windows Preview입니다.
  </p>
  <p>
    <a href="https://github.com/saehajoo/MonglePet/releases/download/windows-v1.4.0-preview.2/MonglePet-Windows-1.4.0.14-x64-Setup.exe">
      Windows용 설치기 다운로드
    </a>
  </p>
  <ul>
    <li>Windows 11 25H2 build 26200 이상, x64</li>
    <li>버전 1.4.0.14 · 약 62.25 MiB</li>
    <li>미서명 Preview · 수동 업데이트</li>
  </ul>
  <p>
    SHA-256:
    <code>C1B8066BFF2BCB1840E594AF668A6E3EF0226FAB5590804594AF3A2E05D64678</code>
  </p>
  <p>
    코드 서명되지 않은 Preview이므로 SmartScreen 경고가 표시될 수 있습니다.
    공식 GitHub Release 파일과 SHA-256이 일치할 때만 실행 여부를 판단해 주세요.
  </p>
  <p>
    <a href="https://github.com/saehajoo/MonglePet/releases/tag/windows-v1.4.0-preview.2">
      릴리스 정보와 체크섬 보기
    </a>
  </p>
</section>

<section aria-labelledby="monglepet-macos-preview-title">
  <h2 id="monglepet-macos-preview-title">MonglePet macOS 1.4.0 Preview 1</h2>
  <p>미서명·미공증 상태로 제공하는 제한된 테스터용 Preview입니다.</p>
  <p>
    <a href="https://github.com/saehajoo/MonglePet/releases/download/macos-v1.4.0-preview.1/MonglePet-1.4.0-build.8-preview.zip">
      macOS용 Preview ZIP 다운로드
    </a>
  </p>
  <ul>
    <li>macOS 14 이상 · Apple Silicon 및 Intel Mac</li>
    <li>버전 1.4.0 (8) · 약 8.42 MiB</li>
    <li>Developer ID 미서명 · Apple 미공증</li>
  </ul>
  <p>
    SHA-256:
    <code>EBB3A12F0B829671399D44E1FD71AB16486E590F46AC1EC57F0C904AECF55820</code>
  </p>
  <p>
    공식 GitHub Release 파일과 SHA-256이 일치할 때만 시스템 설정의
    개인정보 보호 및 보안에서 개별 실행 허용 여부를 판단해 주세요.
  </p>
  <p>
    <a href="https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.4.0-preview.1">
      릴리스 정보·체크섬·빌드 manifest 보기
    </a>
  </p>
</section>
```

## Windows에서 SHA-256 확인

기본 다운로드 폴더에 저장했다면 PowerShell에서 다음 명령을 실행한다.

```powershell
Get-FileHash `
    "$env:USERPROFILE\Downloads\MonglePet-Windows-1.4.0.14-x64-Setup.exe" `
    -Algorithm SHA256
```

출력된 `Hash`가 아래 값과 정확히 같아야 한다.

```text
C1B8066BFF2BCB1840E594AF668A6E3EF0226FAB5590804594AF3A2E05D64678
```

## macOS에서 SHA-256 확인

기본 다운로드 폴더에 저장했다면 터미널에서 다음 명령을 실행한다.

```sh
shasum -a 256 \
  "$HOME/Downloads/MonglePet-1.4.0-build.8-preview.zip"
```

출력된 값이 아래 값과 정확히 같아야 한다.

```text
EBB3A12F0B829671399D44E1FD71AB16486E590F46AC1EC57F0C904AECF55820
```

## 운영 반영 체크리스트

1. Windows와 macOS 버튼이 각각 해당 플랫폼의 버전 고정 URL을 가리키는지 확인한다.
2. 각 카드에 릴리스 정보와 체크섬 링크를 제공하고 macOS에는 빌드 manifest 링크도 제공한다.
3. Windows 최소 버전·x64·미서명·수동 업데이트와 macOS 최소 버전·지원 아키텍처·제한된 테스터용·미서명·미공증 상태를 버튼 근처에 표시한다.
4. 자체 서버에 파일을 복제한다면 공개 URL에서 다시 내려받아 Windows 65,270,050 bytes, macOS 8,833,960 bytes와 각 SHA-256을 확인한다.
5. 브라우저에서 실제 다운로드한 파일명이 원본 설치기 또는 ZIP 이름과 같은지 확인한다.
6. Windows는 기존 `1.4.0.13` 위 업데이트와 데이터 보존을, macOS는 ZIP 해제·응용 프로그램 폴더 이동·시스템 설정의 개별 앱 승인 흐름을 표본 확인한다.
7. 공식 GitHub 링크가 아닌 임의의 미러나 파일 공유 링크를 추가하지 않는다.
8. 보안 기능을 전역 비활성화하거나 quarantine을 제거하는 명령을 안내하지 않는다.
9. 다음 Preview를 게시할 때 기존 버전 파일을 덮어쓰지 않고 새 태그·새 파일·새 체크섬으로 교체한다.

## 현재 알려진 제한

- Windows 설치기와 실행 파일은 코드 서명되지 않았고 앱 안의 자동 업데이트 기능이 아직 없다.
- Windows 혼합 DPI 모니터, 모니터 물리 분리·재연결, 잠금·절전 복귀의 추가 실기기 QA가 남아 있다.
- Smart App Control 또는 조직 정책이 미서명 Windows 앱을 차단하면 현재 Preview를 설치할 수 없을 수 있다.
- macOS ZIP은 Developer ID 미서명·Apple 미공증 상태라 제한된 테스터에게만 제공한다.
- macOS 보안 정책에서 개별 실행을 허용할 수 없는 환경에는 현재 Preview를 제공하지 않는다.
