# Windows 웹 배포와 자동 업데이트 준비

## 상태

- 상태: in_progress
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-16

## 목표

- 자체 웹사이트와 GitHub Releases에서 같은 Windows 릴리스 산출물을 안전하게 배포한다.
- 서명된 버전별 MSIX에서 고정 URL App Installer와 SHA-256 체크섬을 재현 가능하게 만든다.
- 아직 준비되지 않은 인증서나 개발용 Publisher로 공개 릴리스를 만드는 실수를 차단한다.

## 범위

- Windows 웹 배포 구조와 업로드 순서
- 첫 미서명 EXE Preview의 GitHub Release 게시와 자체 웹 다운로드 화면 인계
- MSIX manifest identity 추출
- Authenticode 서명, 인증서 subject, 타임스탬프 검증
- `.appinstaller`와 `SHA256SUMS.txt` 생성 자동화
- 코드 서명과 깨끗한 PC 설치·업데이트 QA 절차

## 제외 범위

- Microsoft Store 제출
- 인증서 또는 원격 서명 서비스 구매
- 웹 커뮤니티 저장소의 다운로드 화면 구현과 운영 서버 배포
- GitHub Actions 서명 자격 증명 구성

## 열린 질문

- 공개 서명에 사용할 인증서 또는 신뢰 가능한 원격 서명 서비스
- 인증서 subject에 맞춘 최종 Publisher 문자열과 표시 이름

## 결정사항

- 자체 웹사이트를 사용자 기본 다운로드 경로로 사용하고 GitHub Releases를 버전 기록과 보조 다운로드 경로로 사용한다.
- 코드 서명 전 첫 EXE는 `Preview`와 수동 업데이트를 명시하고 GitHub Release의 버전 고정 URL과 SHA-256을 웹 다운로드 화면에 전달한다.
- 버전별 MSIX는 변경하지 않는 URL에 두고, 자동 업데이트 진입점인 `MonglePet.appinstaller`만 고정 URL에서 새 버전으로 교체한다.
- 공개 산출물 생성은 Valid 서명, manifest Publisher와 인증서 subject 일치, 타임스탬프를 기본 필수 조건으로 한다.
- MSIX와 체크섬을 먼저 업로드한 뒤 고정 App Installer를 마지막에 교체한다.

## 작업 순서

- [x] 1단계: 현재 MSIX Identity, Publisher와 서명 상태 확인
- [x] 2단계: 버전별 MSIX·App Installer·SHA256SUMS 생성 스크립트 구현
- [x] 3단계: 웹 경로, MIME type, 업로드 순서와 공개 전 QA 문서화
- [ ] 4단계: 공개 코드 서명 방식 선택과 최종 Publisher 확정
- [ ] 5단계: 서명된 MSIX로 산출물 생성 및 깨끗한 PC 최초 설치 QA
- [ ] 6단계: 낮은 버전에서 높은 버전으로 App Installer 업데이트 QA
- [x] 7단계: GitHub Pre-release에 Windows EXE 설치기와 SHA256SUMS 게시
- [ ] 8단계: 별도 서버의 웹 다운로드 화면에 릴리스 링크와 사용자 안내 반영

## 검증 방법

- 기존 1.0.0.13 미서명 MSIX는 기본 실행에서 거부되어야 한다.
- 내부 시험 옵션에서는 패키지 identity와 일치하는 App Installer와 SHA256SUMS가 생성되어야 한다.
- 생성된 XML을 다시 파싱하고 MainPackage의 Name, Publisher, Version, ProcessorArchitecture와 URI를 확인한다.
- SHA256SUMS의 값을 실제 파일 해시와 비교한다.
- 최종 서명된 파일은 `Get-AuthenticodeSignature`가 `Valid`이고 signer subject가 package Publisher와 같아야 한다.
- 미서명 EXE Preview는 병합된 `main`에서 다시 생성하고 실제 업그레이드 설치, 일반 실행, `--startup`, 정상 종료와 사용자 데이터 보존을 확인한다.
- GitHub Release의 원격 asset 크기와 digest가 로컬 최종 설치기·SHA256SUMS와 일치해야 한다.

## 진행 로그

- 2026-08-09: 현재 1.0.0.13 패키지가 `Name=4B7E245F-A59A-4E0F-84D7-52B511356256`, `Publisher=CN=AppPublisher`인 미서명 개발 패키지임을 확인했다.
- 2026-08-09: 공개 기본 경로는 자체 웹사이트, 버전 기록과 보조 다운로드는 GitHub Releases를 사용하기로 했다.
- 2026-08-09: MSIX 내부 identity와 Authenticode를 검증하고 App Installer·SHA256SUMS를 생성하는 PowerShell 스크립트와 운영 절차를 추가했다.
- 2026-08-09: 공개 기본 실행이 `CN=AppPublisher` 개발 패키지를 거부하는 것을 확인했다. 내부 시험 옵션으로 1.0.0.13 산출물을 만들고 App Installer XML의 identity·URI와 MSIX·App Installer SHA-256을 독립 재계산해 일치함을 확인했다.
- 2026-08-16: 병합 커밋 `537d0b18ed38491ff17bf6fb590260231270bd5c`에서 Windows `1.1.0.13` unpackaged 설치기를 다시 생성하고 기존 설치 위 업그레이드, 일반 실행·`--startup`, 전용 메시지 정상 종료, 설정창 숨김·펫 HWND 표시, 전체 HWND 응답, 충돌 0건과 라이브러리 10개 파일 해시 보존을 확인했다.
- 2026-08-16: 태그 `windows-v1.1.0-preview.1`과 GitHub Pre-release `MonglePet Windows 1.1.0 Preview 1`을 게시했다. 설치기 63,829,785 bytes와 원격 digest `sha256:4e1572a58440b8450081b7f4fa90b182d9ef4414ba40f802749139d733e55af7`이 로컬 최종 파일과 일치하고 `SHA256SUMS.txt`도 함께 업로드된 상태를 확인했다.
- 2026-08-16: 별도 서버 소스에는 접근하지 않고 `AGENTS/guides/PREVIEW_DOWNLOAD_HANDOFF.md`에 Windows·macOS 고정 다운로드 URL, 체크섬, 플랫폼별 필수 안내 문구, Markdown·HTML 예시와 운영 반영 체크리스트를 작성했다.
- 2026-08-16: 서버 담당자가 최신 MonglePet `main`의 전달 자료를 단일 원본으로 읽고 기존 서버 스택·디자인·배포 절차 안에서 `/monglepet` 다운로드 카드만 구현하도록 `AGENTS/guides/PREVIEW_DOWNLOAD_SERVER_PROMPT.md`를 추가했다. 릴리스 바이너리 재호스팅과 보안 기능 우회 안내, 커뮤니티 범위 확장을 금지하고 검증·롤백·완료 보고 항목을 명시했다.

## 완료 결과

- 코드 서명 자격 증명 없이 준비할 수 있는 자동화, 첫 Windows EXE GitHub Preview 게시와 웹 다운로드 화면 전달 자료를 완료했다. 자체 웹사이트 반영과 서명된 자동 업데이트 채널은 후속 단계다.

## 남은 위험 / 후속 작업

- 현재 Publisher와 MSIX는 공개용이 아니다. 인증서 또는 원격 서명 서비스를 선택하기 전에는 공개 배포할 수 없다.
- 첫 공개 버전 뒤 Name 또는 Publisher를 바꾸면 기존 설치의 자동 업데이트가 끊긴다.
- App Installer 업데이트는 실제 HTTPS 서버와 깨끗한 Windows 환경에서 최종 검증해야 한다.
- `dev.mapleroom.kr` 다운로드 화면의 소스 수정과 운영 배포는 별도 서버 담당 범위이며 아직 반영되지 않았다.
