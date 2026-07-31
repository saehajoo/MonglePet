# MonglePet Windows Instructions

## 적용 범위

이 파일은 `apps/windows/` 아래의 후속 Windows 앱 작업에 적용한다. 저장소 공통 원칙과 데이터 규격은 루트 `../../AGENTS.md`와 `../../AGENTS/` 문서를 따른다.

## 현재 상태

- Windows 앱은 아직 구현 전이다.
- 기준 기술은 C#·.NET·WinUI 3와 별도 Win32/Composition 펫 오버레이로 확정했다.
- 최소 Windows 버전, 앱 식별자, 테스트 프레임워크와 배포 방식은 별도 구현 계획에서 확정한다.
- Windows 개발·실행 환경과 작업 계획을 준비하기 전 빈 솔루션을 추가하지 않는다.
- 신규 기능은 macOS 기준 구현과 필수 검증이 완료된 뒤 순차 반영한다.

## 기술 기준

- 언어: C#
- 런타임: Windows 구현 시작 시점의 지원 중인 .NET LTS
- 설정 및 일반 앱 UI: Windows App SDK와 WinUI 3
- 펫 오버레이 창: 별도 Win32 `HWND`
- 펫·이동·말풍선 렌더링: `Microsoft.UI.Composition` Visual layer
- 저수준 창·입력·notification area 연동: CsWin32를 우선하는 명시적인 Win32 interop 경계
- WPF: 성능 비교 또는 호환성 대안이며 최종 기준 기술로 사용하지 않음
- C++/WinRT: 전체 앱 구현에는 사용하지 않고 프로파일링으로 확인한 성능 병목 모듈에만 후속 검토

## 구현 원칙

- Windows 네이티브 UI와 운영체제 API를 사용한다.
- macOS Swift·AppKit 소스를 이식하거나 조건부 컴파일로 공유하지 않는다.
- `.monglepet` 패키지, 권장 프로필, 공통 스키마 fixture와 사용자 시나리오만 플랫폼 간 공유한다.
- macOS Bundle Identifier 기반 앱 규칙은 Windows 실행 파일·패키지 식별자와 분리한다.
- 화면 좌표, 모니터 식별자, 시작 프로그램과 창 표시 정책은 Windows 전용 설정·adapter로 구현한다.
- 실제 키 입력 내용, 화면 내용과 창 제목을 수집하지 않는 개인정보 원칙을 유지한다.
- 루트 `../../AGENTS/project/PLATFORM_PARITY.md`의 사용자 동작과 완료 조건을 기준으로 구현 상태를 추적한다.
- macOS 구현 세부사항을 그대로 복제하지 않고 Windows에서 자연스러운 네이티브 UX로 같은 결과를 제공한다.
- 설정 UI 생명주기와 펫 오버레이 생명주기를 분리해 설정창이 닫혀도 오버레이와 notification area가 유지되게 한다.
- 투명·항상 위·비활성·클릭 통과와 다중 모니터 정책은 Win32 `HWND` adapter가 담당한다.
- 프레임 교체, 이동과 말풍선 합성은 UI 스레드의 지속적인 layout·redraw에 의존하지 않고 `Microsoft.UI.Composition`을 우선한다.
- 투명 펫 오버레이를 일반 WinUI 창이나 `SwapChainPanel`에 직접 의존시키지 않는다. 실제 알파 합성과 click-through 동작을 최소 실험에서 먼저 검증한다.
- JSON·ZIP·스키마 마이그레이션, 행동 엔진과 설정 편집은 우선 관리형 C#으로 구현한다.
- C++ 도입은 독립 실행 Release 측정에서 C#·Composition 경로의 병목이 확인되고 관리형 최적화로 기준을 만족하지 못할 때만 별도 계획으로 결정한다.
- C++ 모듈을 추가할 경우 관리형 경계, 소유권, 오류 변환과 자동 테스트를 명시하고 UI·제품 규칙을 넣지 않는다.

## 시작 조건

Windows 구현을 시작하기 전에 별도 작업 계획에서 다음을 확정한다.

1. 최소 Windows 버전, Windows App SDK 버전과 C#·WinUI 3 프로젝트 기준
2. Win32 `HWND`·Composition 투명 항상 위 창, 클릭 통과와 시스템 트레이 방식
3. 전면 앱·입력 없음·다중 모니터 감지 API
4. 설정 저장 위치와 앱 식별자
5. `.monglepet` 호환 fixture와 CPU·GPU·메모리·프레임 지연 성능 기준
6. 실제 Windows Release 빌드에서 고정·마우스 따라가기·자유 이동·도망가기와 말풍선을 포함한 오버레이 성능 실험

## 적용 순서

1. macOS에서 완료된 제품 동작과 공통 명세를 확인한다.
2. Windows 플랫폼 차이와 대체 UX가 필요한 항목을 작업 계획에 기록한다.
3. Windows 네이티브 구현과 플랫폼별 테스트를 작성한다.
4. 공통 fixture의 Windows 왕복과 macOS·Windows 교차 호환을 검증한다.
5. 실제 Windows 환경 QA 후 기능 동등성 현황을 갱신한다.

## 공식 참고

- [Windows 앱 개발 개요](https://learn.microsoft.com/windows/apps/)
- [WinUI 3 개요](https://learn.microsoft.com/windows/apps/winui/winui3/)
- [Windows App SDK 개요](https://learn.microsoft.com/windows/apps/windows-app-sdk/)
- [Composition Visual layer](https://learn.microsoft.com/windows/apps/develop/composition/visual-layer)
- [데스크톱 앱의 Visual layer](https://learn.microsoft.com/windows/uwp/composition/visual-layer-in-desktop-apps)
- [C#에서 Win32 API 호출](https://learn.microsoft.com/windows/apps/develop/interop/call-win32-apis)
