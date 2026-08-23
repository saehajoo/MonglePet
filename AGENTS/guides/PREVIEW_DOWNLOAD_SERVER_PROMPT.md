# Preview 다운로드 화면 서버 전달 프롬프트

아래 프롬프트는 `https://dev.mapleroom.kr/monglepet`을 관리하는 별도 서버 저장소의 Codex나 개발자에게 그대로 전달한다. 서버 저장소의 기술 스택과 배포 규칙을 먼저 확인하고, MonglePet 데스크톱 저장소의 릴리스 계약을 읽은 뒤 작업한다.

---

`https://dev.mapleroom.kr/monglepet`에 MonglePet Windows `1.2.0 Preview`와 macOS `1.2.0 Preview` 다운로드 영역을 구현해 주세요.

## 먼저 확인할 자료

1. 현재 서버 저장소의 최상위 `AGENTS.md`와 관련 하위 지침, README, 배포 문서와 기존 `/monglepet` 구현을 먼저 읽어 주세요.
2. 서버의 프레임워크, 디자인 시스템, 라우팅, 정적 자산, 테스트, staging·production 배포와 롤백 방식을 확인해 주세요. 조사 전에 새 프레임워크나 패키지를 추가하지 마세요.
3. MonglePet 원본 저장소 `https://github.com/saehajoo/MonglePet`의 최신 `main`에서 다음 문서를 읽고, 사용한 원본 commit SHA를 작업 결과에 기록해 주세요.
   - `AGENTS/guides/PREVIEW_DOWNLOAD_HANDOFF.md`
   - `apps/windows/distribution/README.md`
   - `apps/macos/DISTRIBUTION.md`
4. 릴리스 파일명, 크기, SHA-256, 지원 운영체제, 서명 상태와 버전 고정 GitHub URL은 `PREVIEW_DOWNLOAD_HANDOFF.md`를 단일 원본으로 사용하세요. 값을 기억이나 추측으로 다시 작성하지 마세요.

## 작업 범위

- 기존 `/monglepet` 페이지의 정보 구조와 디자인 언어를 유지하면서 앱 다운로드 영역을 추가하거나 갱신합니다.
- 공통 MonglePet Preview 소개 아래에 플랫폼별 최신 버전의 Windows와 macOS 다운로드 카드를 제공합니다.
- Windows 카드는 설치기 직접 다운로드, 릴리스 정보와 체크섬 링크를 제공합니다.
- macOS 카드는 ZIP 직접 다운로드, 릴리스 정보, 체크섬과 빌드 manifest 링크를 제공합니다.
- 각 카드에는 지원 환경, 앱 버전, 파일 크기, 서명 상태, SHA-256과 업데이트 방식을 다운로드 버튼 가까이에 표시합니다.
- 기존 페이지가 반응형이면 같은 breakpoint와 layout 구성요소를 재사용하고, 좁은 화면에서는 두 카드를 자연스럽게 세로로 배치합니다.
- 기존 다국어 체계가 있으면 현재 한국어 페이지 구조에 맞추고, 새로운 번역 시스템은 만들지 않습니다.

## 반드시 유지할 사용자 안내

### Windows

- Windows 11 25H2 build 26200 이상, x64만 지원한다고 표시합니다.
- 현재 사용자 영역에 설치되고 기존 설치 위 수동 업데이트가 가능하며 설정과 펫 라이브러리가 보존된다고 안내합니다.
- 코드 서명과 자동 업데이트가 없는 Preview이며 SmartScreen, Smart App Control 또는 조직 정책에서 경고·차단할 수 있음을 알립니다.
- 공식 GitHub 파일과 SHA-256이 일치할 때만 사용자가 실행 여부를 판단하도록 안내합니다.
- Windows 보안 기능을 전역 비활성화하도록 안내하지 않습니다.

### macOS

- macOS 14 이상, Apple Silicon과 Intel Mac 지원을 표시합니다.
- 일반 공개용이 아닌 `제한된 테스터용 Preview` 상태를 카드 제목 또는 눈에 띄는 상태 표식에 표시합니다.
- Developer ID 미서명·Apple 미공증 상태임을 다운로드 전에 알립니다.
- ZIP 해제 후 `MonglePet.app`을 응용 프로그램 폴더로 이동하는 설치 흐름을 안내합니다.
- 최초 실행이 차단되면 `시스템 설정 → 개인정보 보호 및 보안`의 개별 앱 승인 경로만 안내합니다.
- Gatekeeper 전역 비활성화나 `xattr`을 통한 quarantine 제거 명령을 제공하지 않습니다.

## 다운로드와 파일 처리 경계

- 기본 다운로드 버튼은 `PREVIEW_DOWNLOAD_HANDOFF.md`에 기록된 GitHub Release의 버전 고정 asset URL을 직접 사용합니다.
- 운영 서버에 릴리스 바이너리를 복사하거나 프록시하지 마세요. 기존 운영 정책 때문에 자체 호스팅이 꼭 필요하면 먼저 사용자 승인을 요청하세요.
- 설치기나 ZIP의 파일명을 바꾸거나 다시 압축·변환하지 마세요.
- `latest`처럼 대상이 바뀌는 URL을 만들지 말고 현재 Preview 카드에는 현재 태그의 고정 URL을 사용하세요.
- 이 작업은 데스크톱 앱 다운로드만 다룹니다. `.monglepet` 펫 공유·업로드·커뮤니티 API나 데이터 모델은 변경하지 마세요.

## 접근성과 보안

- 다운로드 링크는 키보드로 접근할 수 있어야 하고 플랫폼, 버전과 파일 형식이 링크 텍스트 또는 접근 가능한 이름에 포함돼야 합니다.
- 색상만으로 Preview·미서명 상태를 구분하지 말고 텍스트를 함께 사용합니다.
- 긴 SHA-256이 모바일 폭을 깨뜨리지 않도록 줄바꿈 또는 복사 가능한 코드 표현을 사용합니다.
- 외부 링크에 새 창 동작을 적용한다면 기존 사이트 정책과 접근성 안내를 따릅니다.
- 기존 CSP, reverse proxy, 인증, 분석 도구나 개인정보 수집 범위를 임의로 변경하지 마세요.
- 다운로드 클릭 추적을 새로 추가하지 마세요. 기존 익명 집계가 있다면 현재 개인정보 정책 범위 안에서만 재사용합니다.

## 구현 순서

1. 서버 저장소와 `/monglepet`의 현재 구조를 조사하고 수정 대상 파일과 배포 경로를 정리합니다.
2. `PREVIEW_DOWNLOAD_HANDOFF.md`의 Markdown·HTML 예시는 콘텐츠 기준으로만 사용하고, 실제 마크업과 스타일은 서버의 기존 구성요소로 구현합니다.
3. 로컬 또는 staging에서 두 다운로드 카드, 반응형 배치, 키보드 접근과 긴 체크섬 표시를 확인합니다.
4. 저장소의 기존 formatter, lint, 단위·통합 테스트와 production build를 실행합니다.
5. 두 GitHub Release와 모든 asset URL, 표시 파일명·크기·SHA-256이 원본 문서와 일치하는지 확인합니다.
6. 기존 배포 절차가 문서화돼 있고 필요한 권한이 있을 때만 staging 검증 후 production에 반영합니다. 권한, 배포 대상 또는 롤백 방식이 불명확하면 운영 변경 전에 중단하고 사용자에게 확인합니다.
7. 배포 후 공개 `/monglepet` 페이지에서 데스크톱·모바일 레이아웃, 실제 다운로드 응답과 보안 안내를 확인합니다.

## 완료 보고

다음을 보고해 주세요.

- 사용한 MonglePet 원본 commit SHA
- 서버 저장소에서 수정한 파일
- 적용한 Windows·macOS 다운로드 URL과 표시 버전
- 실행한 formatter, lint, 테스트와 build 결과
- staging·production 반영 여부와 공개 페이지 URL
- 실제 다운로드 링크와 파일명 확인 결과
- 롤백 방법
- 남은 제한 또는 사용자 확인이 필요한 사항

운영 서버의 소스나 설정을 직접 즉흥 수정하지 말고, 서버 저장소의 정상적인 commit·review·배포 절차를 사용해 주세요.

---
