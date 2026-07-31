# MonglePet for Windows

Windows 버전의 플랫폼 디렉터리다. 현재는 구현 전이며 기준 기술은 **C# + .NET + WinUI 3 + Win32/Microsoft.UI.Composition**으로 확정했다.

Windows 앱은 macOS 앱과 기능 동등성을 목표로 하되 네이티브 프로젝트로 별도 구현한다. 공유 범위는 `.monglepet` 패키지 규격, 권장 프로필, 스키마 fixture와 공통 테스트 시나리오로 제한한다.

설정 및 일반 앱 UI는 WinUI 3로 구현하고, 펫은 별도 Win32 `HWND`와 `Microsoft.UI.Composition` Visual layer로 표시한다. 행동 엔진과 데이터 처리는 C#에 유지하고 Win32 API는 창, notification area, 전면 앱·입력 없음과 다중 모니터 감지 경계에서 사용한다.

WPF는 초기 성능 비교 또는 호환성 대안일 뿐 최종 기준 기술이 아니다. C++/WinRT도 전체 앱 언어로 사용하지 않고 실제 Windows Release 측정에서 관리형 렌더링 병목이 확인된 모듈에만 후속 검토한다.

구현을 시작하기 전 `AGENTS.md`의 시작 조건과 루트 작업 계획을 먼저 확인한다.
