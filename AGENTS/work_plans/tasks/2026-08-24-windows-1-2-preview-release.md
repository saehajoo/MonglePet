# Windows 1.2.0 Preview 배포

## 상태

- 상태: completed
- 생성일: 2026-08-24
- 마지막 갱신: 2026-08-24

## 목표

- Windows 웹 펫 URL 가져오기와 최신 펫 보관함 UI를 `1.2.0.13` Preview로 검증하고 GitHub Pre-release에 게시한다.
- 기존 `1.1.0.13` EXE 설치 위 업데이트에서 `%LOCALAPPDATA%\MonglePet` 설정과 펫 라이브러리가 유지되는 배포 계약을 보존한다.

## 범위

- Windows 마케팅·파일·MSIX 버전과 버전 계약 테스트 갱신
- 웹 URL 가져오기 관련 테스트를 포함한 Debug·Release 전체 빌드와 테스트
- unsigned self-contained x64 EXE 설치기와 `SHA256SUMS.txt` 생성
- 설치기 버전·서명 상태·크기·SHA-256과 깨끗한 산출물 검증
- `windows-v1.2.0-preview.1` GitHub Pre-release 게시와 원격 digest 재검증
- Windows 배포 문서, 웹 다운로드 인계와 플랫폼 현황 갱신

## 제외 범위

- 코드 서명, Microsoft Store와 App Installer 자동 업데이트
- 자체 웹사이트 저장소 수정과 운영 서버 배포
- Windows 웹 가져오기의 운영 URL·Narrator·혼합 DPI 후속 QA
- macOS 소스와 이미 게시한 macOS `1.2.0 (3)` 산출물 변경

## 결정사항

- 앱 마케팅 버전은 `1.2.0`, Assembly·File·MSIX 버전은 `1.2.0.13`으로 한다.
- 태그는 `windows-v1.2.0-preview.1`, 릴리스 이름은 `MonglePet Windows 1.2.0 Preview 1`로 한다.
- 기존 Windows 패키지 identity와 Inno Setup `AppId`를 유지한다.
- 코드 서명 자격 증명이 없으므로 미서명 EXE 설치기만 Preview로 게시한다.
- 릴리스 태그는 검증된 설치기를 만든 소스 커밋을 가리키며 산출물 메타데이터 문서 커밋은 필요하면 뒤에 분리한다.

## 작업 순서

### Windows

- [x] 1단계: 원격 `main`, 기존 릴리스와 버전·태그 충돌 여부를 확인한다.
- [x] 2단계: 버전을 `1.2.0.13`으로 올리고 버전 계약 테스트를 추가한다.
- [x] 3단계: Debug·Release 전체 빌드와 테스트, `git diff --check`를 통과한다.
- [x] 4단계: 소스 변경을 커밋·푸시하고 검증된 커밋에서 설치기를 생성한다.
- [x] 5단계: 기존 설치 위 업데이트와 사용자 데이터 보존을 확인한다.
- [x] 6단계: GitHub Pre-release를 게시하고 원격 산출물 digest를 재검증한다.

### 플랫폼 동등성

- [x] 7단계: 배포·웹 다운로드 인계 문서와 플랫폼 현황을 최종 갱신한다.

## 검증 방법

- `MonglePet.Shell.Tests` 버전·protocol 계약 테스트를 먼저 실행한다.
- 저장소 표준 명령으로 Debug·Release 전체 빌드와 테스트를 실행한다.
- `New-WindowsExeInstaller.ps1 -AllowUnsigned`로 설치기와 체크섬을 생성한다.
- 게시 실행 파일과 설치기의 버전, 미서명 상태, 파일 크기와 SHA-256을 확인한다.
- 기존 설치 위 업데이트 전후 `%LOCALAPPDATA%\MonglePet` 파일 SHA-256을 비교한다.
- GitHub Release 자산을 다시 내려받아 로컬 최종 산출물과 digest가 같은지 확인한다.

## 진행 로그

- 2026-08-24: 원격 `main`의 macOS 1.2.0 릴리스 커밋을 현재 Windows 작업에 반영하고 공통 문서 충돌을 두 플랫폼 기록이 모두 남도록 해결했다.
- 2026-08-24: 기존 `windows-v1.1.0-preview.1` 다음 Windows 기능 버전을 `1.2.0.13`, 태그를 `windows-v1.2.0-preview.1`로 확정했다.
- 2026-08-24: Shell 버전 계약 테스트 20개와 Debug·Release 전체 빌드·각 235개 테스트, `git diff --check`가 통과했다. NuGet 취약성 metadata endpoint의 `NU1900` 경고 3개만 남았다.
- 2026-08-24: 기존 `1.1.0.13` 개발 MSIX를 `1.2.0.13`으로 등록 업데이트해 LocalState 22개 파일의 크기·SHA-256 차이 0개를 확인했다. packaged 실제 개발 URL이 검토 화면을 열었고 취소 뒤 라이브러리 차이와 임시 폴더가 0개였다.
- 2026-08-24: 최종 EXE 설치기 업그레이드 QA에서 전용 종료 뒤 WinUI 창·트레이는 닫히지만 프로세스가 남는 결함을 재현했다. 마지막 창을 닫기 전에 낮은 우선순위 `Application.Exit`를 예약해 대기 중 XAML 저장 이벤트를 먼저 소진하면서 프로세스 종료를 보장하도록 수정했다.
- 2026-08-24: 종료 수정 뒤 Debug·Release 전체 빌드와 각 235개 테스트가 다시 통과했다. 수정된 unpackaged Release publish는 실제 개발 URL 검토·취소와 임시 폴더 0개를 확인한 뒤 전용 종료 메시지만으로 프로세스가 0개가 됐다.
- 2026-08-24: 웹 가져오기 PR #6과 종료 수정 PR #7을 병합했다. 최종 릴리스 소스는 `3ee61a22979a12c42cdaf7d7bbc2c0b08640792b`이다.
- 2026-08-24: 최종 소스에서 63,847,413 bytes의 `MonglePet-Windows-1.2.0.13-x64-Setup.exe`와 `SHA256SUMS.txt`를 만들었다. 설치기 SHA-256은 `95C4446A42266E279D55138862EE4E2076BA46661F33E4FAFAA26D4CDF064A8A`이다.
- 2026-08-24: 최종 설치기를 기존 설치 위에 적용해 `%LOCALAPPDATA%\MonglePet` 11개 파일 차이 0개, protocol 검토·취소, 라이브러리 10개 파일 차이 0개, 임시 폴더 0개와 종료 뒤 프로세스 0개를 확인했다.
- 2026-08-24: 태그 `windows-v1.2.0-preview.1`의 GitHub Pre-release를 게시하고 자산을 다시 내려받아 설치기 크기·SHA-256과 체크섬 파일이 로컬 최종본과 일치함을 확인했다.

## 완료 결과

- Windows `1.2.0.13` 미서명 x64 EXE 설치기와 SHA256SUMS 생성, 기존 설치 업데이트·데이터 보존·실제 URL 검토·정상 종료 QA와 GitHub Pre-release 게시를 완료했다.
- 릴리스 URL은 `https://github.com/saehajoo/MonglePet/releases/tag/windows-v1.2.0-preview.1`이다.

## 남은 위험 / 후속 작업

- 미서명 설치기는 SmartScreen·Smart App Control·조직 정책에서 경고하거나 차단될 수 있다.
- 자체 웹 다운로드 화면 갱신은 별도 서버 저장소 담당자에게 최종 링크와 digest를 전달해야 한다.
- 개발 MSIX와 공개 EXE가 동시에 등록된 현재 PC에서는 Windows Shell의 같은 scheme 선택이 실행되지 않았다. 각 채널의 정확한 activation 명령은 통과했으며 실제 사용자와 같은 EXE 단독 깨끗한 계정의 association QA가 남아 있다.
