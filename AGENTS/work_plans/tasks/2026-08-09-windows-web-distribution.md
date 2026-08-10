# Windows 웹 배포와 자동 업데이트 준비

## 상태

- 상태: in_progress
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- 자체 웹사이트와 GitHub Releases에서 같은 Windows 릴리스 산출물을 안전하게 배포한다.
- 서명된 버전별 MSIX에서 고정 URL App Installer와 SHA-256 체크섬을 재현 가능하게 만든다.
- 아직 준비되지 않은 인증서나 개발용 Publisher로 공개 릴리스를 만드는 실수를 차단한다.

## 범위

- Windows 웹 배포 구조와 업로드 순서
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
- [ ] 7단계: 웹 다운로드 화면과 GitHub Release에 동일 산출물 게시

## 검증 방법

- 기존 1.0.0.13 미서명 MSIX는 기본 실행에서 거부되어야 한다.
- 내부 시험 옵션에서는 패키지 identity와 일치하는 App Installer와 SHA256SUMS가 생성되어야 한다.
- 생성된 XML을 다시 파싱하고 MainPackage의 Name, Publisher, Version, ProcessorArchitecture와 URI를 확인한다.
- SHA256SUMS의 값을 실제 파일 해시와 비교한다.
- 최종 서명된 파일은 `Get-AuthenticodeSignature`가 `Valid`이고 signer subject가 package Publisher와 같아야 한다.

## 진행 로그

- 2026-08-09: 현재 1.0.0.13 패키지가 `Name=4B7E245F-A59A-4E0F-84D7-52B511356256`, `Publisher=CN=AppPublisher`인 미서명 개발 패키지임을 확인했다.
- 2026-08-09: 공개 기본 경로는 자체 웹사이트, 버전 기록과 보조 다운로드는 GitHub Releases를 사용하기로 했다.
- 2026-08-09: MSIX 내부 identity와 Authenticode를 검증하고 App Installer·SHA256SUMS를 생성하는 PowerShell 스크립트와 운영 절차를 추가했다.
- 2026-08-09: 공개 기본 실행이 `CN=AppPublisher` 개발 패키지를 거부하는 것을 확인했다. 내부 시험 옵션으로 1.0.0.13 산출물을 만들고 App Installer XML의 identity·URI와 MSIX·App Installer SHA-256을 독립 재계산해 일치함을 확인했다.

## 완료 결과

- 코드 서명 자격 증명 없이 준비할 수 있는 배포 자동화와 문서화는 완료했다.

## 남은 위험 / 후속 작업

- 현재 Publisher와 MSIX는 공개용이 아니다. 인증서 또는 원격 서명 서비스를 선택하기 전에는 공개 배포할 수 없다.
- 첫 공개 버전 뒤 Name 또는 Publisher를 바꾸면 기존 설치의 자동 업데이트가 끊긴다.
- App Installer 업데이트는 실제 HTTPS 서버와 깨끗한 Windows 환경에서 최종 검증해야 한다.
