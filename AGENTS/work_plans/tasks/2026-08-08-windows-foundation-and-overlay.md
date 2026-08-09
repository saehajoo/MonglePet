# Windows 개발 기준선·공통 계약·오버레이 실험

## 상태

- 상태: complete
- 생성일: 2026-08-08
- 마지막 갱신: 2026-08-08

## 목표

- Windows 앱을 구현할 수 있는 재현 가능한 C#·WinUI 3 개발 환경과 솔루션 기준선을 만든다.
- `.monglepet` 공통 계약을 Windows에서 검증할 수 있는 관리형 로더와 테스트 기반을 만든다.
- 별도 Win32 `HWND`와 `Microsoft.UI.Composition` 오버레이가 실제 Windows Release 환경에서 투명도·항상 위·클릭 통과와 성능 기준을 만족하는지 먼저 검증한다.

## 범위

- ZIP 작업 폴더를 원격 `main` 이력과 연결하고 기준 커밋 확인
- Windows 11 25H2, .NET 10 LTS, Windows App SDK 2.3.1 Stable과 Visual Studio 2026 개발 기준 고정
- x64 우선, packaged WinUI 3·MSIX 기준의 단일 프로세스 솔루션 생성
- 순수 C# Domain, 패키지 계약과 xUnit 테스트 프로젝트 생성
- 공통 `.monglepet` 정상·오류 fixture 정리와 Windows 로더 왕복 검증
- 별도 Win32 오버레이 `HWND`와 Composition 프레임 표시 성능 실험
- 실제 Release 측정 결과에 따른 후속 아키텍처 판단

## 제외 범위

- 전체 설정 UI와 펫 스튜디오
- 자동·수동 행동 전체 런타임
- 전면 앱·입력 없음·잠금·절전 adapter 전체 구현
- 이동·다중 모니터·쓰다듬기·말풍선 완성
- Microsoft Store 등록, 코드 서명과 공개 설치 프로그램
- C++/WinRT 모듈 도입

## 열린 질문

- MSIX 배포용 최종 Package Identity와 Publisher는 서명·배포 준비 작업에서 확정한다.
- Windows 자동 규칙의 앱 대상은 Package Family Name·AppUserModelID 우선과 실행 파일 fallback을 비교한 뒤 별도 결정한다.
- ARM64 지원은 x64 Release 기준선 통과 뒤 별도 작업으로 추가한다.

## 결정사항

- 최소 지원 OS는 Windows 11 25H2 build 26200으로 한다.
- 관리형 런타임은 .NET 10 LTS, 일반 UI는 Windows App SDK 2.3.1 Stable의 WinUI 3를 사용한다.
- 초기 배포·디버그 기준은 packaged WinUI 3와 MSIX이며 앱, 설정창, notification area와 오버레이는 하나의 full-trust 프로세스에서 수명주기만 분리한다.
- 초기 빌드 대상은 x64이며 Core·패키지 자동 검증은 xUnit으로 작성한다.
- Windows 사용자 데이터는 `%LOCALAPPDATA%\MonglePet` 아래의 버전 지정 JSON과 `Library/<installation-uuid>`에 저장한다. 화면·앱 식별자는 Windows 로컬 데이터로만 유지한다.
- 첫 성능 합격 기준은 유휴 CPU 평균 1% 미만, 이동 CPU 평균 5% 미만·10% 이상 지속 없음, warm-up 뒤 private memory 200MiB 이하·1시간 증가 10MiB 이하, 프레임 표시 지연 p95 33ms 이하로 시작한다.
- C++/WinRT는 관리형 경로를 프로파일링하고 최적화한 뒤에도 기준을 넘는 독립 병목이 확인될 때만 별도 계획으로 검토한다.

## 작업 순서

- [x] 1단계: 원격 Git 이력 연결과 ZIP 내용의 기준 커밋 일치 확인
- [x] 2단계: Windows 최소 버전·도구 체인·배포·테스트·성능 기준 결정
- [x] 3단계: Visual Studio 2026·.NET 10·WinUI 개발 환경 설치와 확인
- [x] 4단계: C# 솔루션·Core·Packages·Windows App·테스트 프로젝트 생성
- [x] 5단계: 공통 패키지 계약과 정상·오류 fixture 추가
- [x] 6단계: Windows `.monglepet` 로더와 xUnit 호환 테스트
- [x] 7단계: Win32 `HWND`·Composition 투명 오버레이 최소 실험
- [x] 8단계: 독립 실행 Release 측정과 후속 구조 결정
- [x] 9단계: 문서·플랫폼 동등성 현황과 검증 결과 갱신

## 검증 방법

- `dotnet --info`와 설치된 Windows SDK·Windows App SDK·Visual Studio workload 확인
- `dotnet restore`, `dotnet build -c Debug`, `dotnet test -c Debug`
- `shared` 정상·오류 fixture의 Windows 로더 결과와 macOS 기준 결과 비교
- x64 Release 독립 실행에서 투명도, 항상 위, 비활성, 클릭 통과와 notification area 수동 QA
- 고정·이동·말풍선 workload의 CPU·GPU·private memory·프레임 지연 기록
- `git diff --check`와 Windows 문서 링크·명령 확인

## 진행 로그

- 2026-08-08: ZIP 작업 폴더의 202개 파일이 `origin/main`의 `adc1f7741786e7eda4b0ec9d4c7de7ab36bdff52`와 일치함을 확인하고 현재 폴더를 `main` 추적 작업 트리로 연결했다.
- 2026-08-08: 현재 PC가 x64 Windows 25H2 build 26200.8875이며 WinGet은 있지만 .NET SDK·Visual Studio·MSBuild와 개발자 모드는 준비되지 않은 상태임을 확인했다.
- 2026-08-08: .NET 10 LTS, Windows App SDK 2.3.1 Stable, Windows 11 25H2와 초기 x64·MSIX·xUnit 기준을 확정했다.
- 2026-08-08: Visual Studio Community 2026 18.8.2, .NET SDK 10.0.302, WinUI C# 지원과 Windows 개발자 모드를 설치·확인했다.
- 2026-08-08: `MonglePet.slnx`와 Core·Packages·WinUI 앱·xUnit 테스트 프로젝트를 생성하고 Windows App SDK 2.3.1, x64 packaged MSIX 기준으로 정리했다.
- 2026-08-08: macOS 행동 결정 우선순위를 C# Domain에 옮기고 공통 샘플의 레거시 `license`를 무시하는 `pet.json` 구조 검증을 추가했다. ZIP·실제 이미지 검증은 5~6단계의 남은 범위다.
- 2026-08-08: x64 Debug 솔루션 전체가 경고 없이 빌드되었고 행동 엔진 8개·패키지 manifest 7개, 총 15개 xUnit 테스트가 통과했다.
- 2026-08-08: 생성된 MSIX manifest가 최소·검증 Windows build 26200을 유지하도록 빌드 단계를 보정했고, loose-layout 개발 패키지에서 `MonglePet` WinUI 창의 정상 시작·응답을 확인한 뒤 테스트 등록을 제거했다.
- 2026-08-08: CsWin32로 별도 220×220 Win32 `WS_POPUP` 부모 창을 만들고 `ContentIsland`·`DesktopChildSiteBridge`로 `Microsoft.UI.Composition` 임시 펫 비주얼을 연결했다. packaged 앱에서 부모·자식 HWND의 가시성과 일치 좌표, 항상 위·비활성·도구 창·클릭 통과 스타일을 확인하고 개발 UI에 표시·숨김과 입력 통과 제어를 추가했다.
- 2026-08-08: 공식 C++ 예제의 `ICompositorDesktopInterop` 경로는 현재 C#·Windows App SDK 2.3.1 런타임에서 `E_NOINTERFACE`로 실패해 원시 ABI 호출을 제거하고 공개 ContentIsland API로 대체했다. Release CPU·메모리·프레임 지연과 실제 이미지 재생은 8단계로 남겼다.
- 2026-08-08: macOS와 같은 20 MiB 압축·100 MiB 해제·2,000 엔트리·100:1 압축률 상한과 경로 탈출·링크·실행 파일 차단을 적용한 디렉터리·ZIP 로더를 추가했다. PNG·WebP 정적 컨테이너, 크기·알파 선언과 manifest 참조를 검사하고 공통 PNG fixture를 실제 Windows 이미지 디코더로 표시한다.
- 2026-08-08: 프레임 반복·종료 상태를 단위 테스트 가능한 모델로 분리하고 `LoadedImageSurface`·`CompositionSurfaceBrush`의 scale/offset으로 atlas 프레임을 표시했다. packaged Release 앱 접근성 상태에서 `읽기 전용 샘플 · 재생 중`, `idle 1/1`, 별도 HWND 표시와 클릭 통과를 확인했다.
- 2026-08-08: 연결 실험용 무한 호흡 애니메이션이 첫 30초 측정에서 전체 시스템 CPU 3.133%를 사용해 제거했다. 5초 warm-up 뒤 30초 재측정은 CPU 0.017%(단일 코어 환산 0.103%), private memory 평균·최대 100.2 MiB, working set 평균 144.9 MiB, 3D GPU 평균·최대 0%로 고정 workload 기준을 통과했다.
- 2026-08-08: x64 Release 전체 빌드가 경고·오류 없이 통과하도록 트리밍·ReadyToRun을 자체 포함 배포에서만 활성화하도록 수정했다. Core 8개·Packages 17개, 총 25개 xUnit 테스트가 통과했다.

## 완료 결과

- C#·WinUI 3 Windows 개발 기준선, 공통 패키지 보안 로더와 실제 Composition PNG 프레임 경로를 만들었다.
- x64 Debug·Release 빌드, 25개 단위 테스트, packaged Release 실제 실행과 고정 workload 성능 기준선을 통과했다.
- 관리형 C#·Composition 경로가 현재 고정 workload 기준을 충분히 만족하므로 C++/WinRT 모듈은 도입하지 않는다.

## 남은 위험 / 후속 작업

- 실제 다중 프레임·WebP, 이동·말풍선 workload, 프레임 지연 p95와 1시간 메모리 증가는 기능 구현과 함께 후속 측정해야 한다.
- 설치 전 모든 미리보기·atlas의 실제 이미지 디코딩과 CRC 수준 이미지 무결성 검증을 보강해야 한다.
- Package Identity, Publisher, 서명과 업데이트 채널은 공개 배포 작업에서 별도 확정해야 한다.
- 전체 기능 동등성은 이 기반 작업 뒤 설정·행동, 활동 감지, 이동·상호작용, 말풍선·공유와 배포 작업으로 나눠 진행한다.
