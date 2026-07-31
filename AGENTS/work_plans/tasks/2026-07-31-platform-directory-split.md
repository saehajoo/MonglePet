# macOS·Windows 플랫폼 디렉터리 분리

## 상태

- 상태: completed
- 생성일: 2026-07-31
- 마지막 갱신: 2026-07-31

## 목표

- 하나의 저장소에서 macOS와 Windows 앱을 독립적으로 개발할 수 있도록 플랫폼 디렉터리를 분리한다.
- 공통 문서, 라이선스, `.monglepet` 샘플과 스키마 규격은 저장소 루트에서 함께 관리한다.
- 기존 macOS Xcode 프로젝트의 빌드·테스트·배포 경로를 새 구조에서도 유지한다.

## 범위

- `apps/macos/`로 Xcode 프로젝트, 소스, 테스트, UI 테스트, 배포 문서와 스크립트 이동
- `apps/windows/`에 후속 네이티브 구현을 위한 안내와 작업 지침 추가
- `shared/Samples/`로 플랫폼 공통 `.monglepet` 샘플 이동
- 루트 `AGENTS.md`, `README.md`, 프로젝트 문서와 명령 경로 동기화
- Debug 빌드와 전체 macOS 단위 테스트

## 제외 범위

- Windows UI 프레임워크와 최소 지원 버전 확정
- Windows 솔루션·실행 파일·설치 프로그램 생성
- Swift와 C# 사이의 소스 코드 공유
- 기존 macOS 앱의 제품 동작·저장 위치·Bundle Identifier 변경
- 공통 명세 문서를 별도 디렉터리로 추가 이동

## 열린 질문

- 없음

## 결정사항

- 하나의 저장소 안에서 `apps/macos`, `apps/windows`, `shared`를 사용한다.
- 각 플랫폼 앱은 독립적인 네이티브 프로젝트와 빌드 체계를 가진다.
- 플랫폼 간에는 `.monglepet` 규격, 권장 프로필, 스키마 fixture와 테스트 시나리오만 공유한다.
- 기존 macOS 프로젝트 구성 요소는 같은 상대 구조를 유지한 채 함께 이동해 Xcode 프로젝트 참조 변경을 최소화한다.
- Windows 프로젝트는 기술 결정을 확정하기 전 빈 솔루션을 만들지 않는다.

## 작업 순서

- [x] 1단계: 플랫폼 분리 결정과 작업 문서 작성
- [x] 2단계: macOS 프로젝트·배포 파일과 공통 샘플 이동
- [x] 3단계: 플랫폼별 AGENTS와 안내 문서 추가
- [x] 4단계: 루트 문서·명령·스크립트 경로 수정
- [x] 5단계: 전체 단위 테스트, Debug 빌드와 경로 검증

## 검증 방법

- `apps/macos/MonglePet.xcodeproj` 기준 Debug 빌드
- 전체 `MonglePetTests`
- 배포 스크립트의 프로젝트·저장소 루트 계산과 문법 검사
- 루트 문서와 작업 문서의 옛 프로젝트 경로 검색
- 작업 계획 인덱스와 Markdown 링크 대상 확인

## 진행 로그

- 2026-07-31: 현재 Xcode 프로젝트의 소스·테스트 그룹이 프로젝트 위치 기준 상대 경로를 사용해 관련 디렉터리를 함께 이동할 수 있음을 확인했다.
- 2026-07-31: 루트 공통 문서·라이선스, `apps/macos`, `apps/windows`, `shared/Samples` 구조를 확정했다.
- 2026-07-31: macOS Xcode 프로젝트·소스·테스트·배포 자동화를 `apps/macos`로, 공통 펫 샘플을 `shared/Samples`로 이동했다.
- 2026-07-31: 플랫폼별 `AGENTS.md`와 안내 문서, 루트 README·아키텍처·로드맵·결정 기록·테스트 명령을 새 구조에 맞췄다.
- 2026-07-31: 두 배포 스크립트의 저장소·macOS 프로젝트 루트 계산과 zsh 문법 검사를 통과했다.
- 2026-07-31: 새 Xcode 경로에서 전체 단위 XCTest 388개 통과, 선택적 로컬 WebP fixture 1개 건너뜀과 Debug 빌드 성공을 확인했다.
- 2026-07-31: 후속 지침 정리에서 macOS 기준 구현 후 Windows 순차 반영 절차와 기능별 진행 상태를 `PLATFORM_PARITY.md`에 추가했다.
- 2026-07-31: Windows 기준 기술을 C#·.NET·WPF로 확정하고 Windows App SDK·Win32 interop의 제한적 사용과 C++ 도입 조건을 플랫폼 지침에 기록했다.
- 2026-07-31: 성능과 기능 우선 재검토 결과 D-058을 D-059로 대체했다. C#·.NET은 유지하고 WinUI 3 설정 UI와 별도 Win32 `HWND`·Microsoft.UI.Composition 펫 오버레이로 기준을 변경했다.

## 완료 결과

- macOS 앱과 전용 배포 파일은 `apps/macos/`에서 독립적으로 빌드·테스트할 수 있다.
- Windows 구현 전용 `apps/windows/` 진입점과 시작 조건을 마련했다.
- 공통 `.monglepet` 수동 검증 샘플을 `shared/Samples/`로 이동했다.
- 루트 공통 문서와 플랫폼별 지침이 새 경로를 안내하며 기존 macOS 제품 동작과 Bundle Identifier는 변경하지 않았다.

## 남은 위험 / 후속 작업

- Windows 앱 식별자와 자동 규칙의 앱 대상 표현은 Windows 기술 설계에서 별도로 확정해야 한다.
- 기존 자동 규칙의 macOS Bundle Identifier를 Windows 실행 파일 식별자와 직접 공유하지 않는다.
