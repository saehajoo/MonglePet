# Windows unpackaged EXE 설치기

## 상태

- 상태: completed
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- 기존 packaged MSIX 채널을 보존하면서 웹에서 배포할 수 있는 unpackaged WinUI 3 self-contained 앱과 사용자별 EXE 설치기를 추가한다.
- 펫·행동·오버레이 기능을 바꾸지 않고 패키지 Identity에 의존하는 저장소, 자동 실행, 버전과 업데이트 경계를 실행 환경별 adapter로 분리한다.
- 미서명 설치기의 SmartScreen 경고와 이후 코드 서명 가능성을 명확히 문서화한다.

## 범위

- packaged/unpackaged 실행 환경 감지와 로컬 데이터 루트 선택
- 기존 MSIX LocalState에서 unpackaged `%LOCALAPPDATA%\MonglePet`로 한 번만 복사하는 마이그레이션
- MSIX StartupTask와 unpackaged 사용자별 자동 실행 adapter
- Assembly/FileVersion 기반 unpackaged 버전 표시
- .NET·Windows App SDK self-contained x64 publish 프로필
- `%LOCALAPPDATA%\Programs\MonglePet` 사용자별 설치, 시작 메뉴와 제거 항목을 제공하는 EXE 설치기
- 기존 설치 위 업그레이드, 사용자 데이터 보존과 제거 검증

## 제외 범위

- 설치기·앱 코드 서명 인증서 구매
- 첫 단계의 무인 자동 업데이트 다운로드·적용
- x86·ARM64 설치기
- MSIX 채널 제거
- Store 제출

## 열린 질문

- 없음. 첫 EXE 채널은 웹 수동 업데이트와 x64 사용자별 설치로 고정한다.

## 결정사항

- EXE 설치기는 MSIX를 감싸는 bootstrapper가 아니라 package Identity가 없는 unpackaged WinUI 3 앱을 설치한다.
- 앱과 Windows App SDK·.NET 런타임 파일은 설치기에 함께 넣고 단일 파일 앱 실행본을 요구하지 않는다.
- 설치 경로는 관리자 권한이 필요 없는 `%LOCALAPPDATA%\Programs\MonglePet`, 데이터 경로는 `%LOCALAPPDATA%\MonglePet`로 고정한다.
- 설치기 AppId와 데이터 경로는 첫 Preview부터 고정해 이후 서명된 설치기가 같은 설치를 업그레이드할 수 있게 한다.
- 제거 기본 동작은 사용자 설정과 펫 라이브러리를 보존한다.
- 기존 MSIX 데이터는 대상 unpackaged 데이터가 비어 있을 때만 알려진 현재 package family LocalState에서 복사하며 원본은 삭제하지 않는다.

## 작업 순서

- [x] 1단계: 현재 Package Identity 의존 코드와 설치 도구 환경 조사
- [x] 2단계: 실행 환경·저장 경로·버전 adapter와 테스트
- [x] 3단계: unpackaged 자동 실행과 LocalState 마이그레이션 및 테스트
- [x] 4단계: self-contained unpackaged publish 프로필과 빌드 검증
- [x] 5단계: 사용자별 EXE 설치기 구성과 생성
- [x] 6단계: 새 설치·업그레이드·제거·재실행 수동 QA
- [x] 7단계: 아키텍처·결정·로드맵·동등성·사용자 배포 문서 갱신

## 검증 방법

- packaged 빌드는 기존 ApplicationData LocalState와 StartupTask를 계속 사용한다.
- unpackaged 실행은 `%LOCALAPPDATA%\MonglePet`에서 설정과 라이브러리를 저장하고 재실행 복원한다.
- 기존 MSIX LocalState 복사는 대상이 비어 있을 때 한 번만 수행하고 원본을 변경하지 않는다.
- unpackaged 자동 실행 켜기·끄기가 현재 사용자 범위에만 적용되고 다른 실행 경로의 값을 덮어쓰지 않는다.
- clean publish 출력만 있는 환경에서 앱이 실행되고 펫·설정창·notification area가 표시된다.
- 같은 AppId 설치기를 다시 실행하면 기존 앱을 업그레이드하고 사용자 데이터가 유지된다.
- 제거 뒤 실행 파일·시작 메뉴·자동 실행 항목은 없어지고 `%LOCALAPPDATA%\MonglePet`은 남는다.
- 전체 171개 Windows 단위 테스트와 x64 Debug·Release packaged 빌드가 회귀 없이 통과한다.

## 진행 로그

- 2026-08-09: 현재 package 의존성이 `ApplicationData.Current.LocalFolder`, `StartupTask`, `Package.Current.Id.Version` 세 경계에 집중되어 있고 Core·패키지·설정·오버레이·activity 계층은 그대로 재사용할 수 있음을 확인했다.
- 2026-08-09: 설치기 컴파일러는 아직 설치되어 있지 않고 Windows Package Manager만 사용할 수 있음을 확인했다.
- 2026-08-09: package identity 감지, 데이터 루트·버전 분기, Run 자동 실행과 기존 MSIX LocalState 비파괴 이전을 구현하고 Shell 테스트 12개를 통과했다.
- 2026-08-09: .NET·Windows App SDK self-contained x64 publish 538개 파일 약 225.05MiB와 Inno Setup 6.7.3 기반 약 60.8MiB 설치기·SHA256SUMS를 생성했다.
- 2026-08-09: 사용자별 최초 설치, 동일 버전 업그레이드, `--startup` 숨김 실행, MSIX 데이터 11개 이전과 원본 보존을 확인했다.
- 2026-08-09: 실행 중 제거가 처음에는 WinUI 프로세스를 닫지 못하는 문제를 찾아 전용 notification area 종료 메시지를 추가했다. 재검증에서 프로세스·설치 폴더·바로가기·제거 항목·자동 실행 값이 모두 없어지고 사용자 데이터 해시가 보존됐다.

## 완료 결과

- packaged·unpackaged 실행 경계를 분리하고 첫 웹 Preview용 x64 EXE 설치기 생성과 실제 설치 수명주기 검증을 완료했다.

## 남은 위험 / 후속 작업

- 미서명 EXE는 SmartScreen·Smart App Control·기업 정책에 의해 경고 또는 차단될 수 있다.
- 코드 서명 없이 제공하는 SHA-256은 파일 무결성 보조 수단일 뿐 배포자 신원을 증명하지 않는다.
- 자동 업데이트는 첫 EXE 릴리스의 수동 설치·업그레이드 안정화 후 별도 작업으로 추가한다.
