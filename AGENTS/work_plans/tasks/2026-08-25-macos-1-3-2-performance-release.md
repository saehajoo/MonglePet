# macOS 1.3.2 이동 런타임 성능 보정 Preview 릴리스

## 상태

- 상태: in_progress
- 생성일: 2026-08-25
- 마지막 갱신: 2026-08-25

## 목표

- macOS `1.3.1 (6)` 공개 뒤 완료한 이동 런타임 비용 보정을 `1.3.2 (7)` Preview로 게시한다.
- 이동 33ms cadence·속도·애니메이션과 사용자 동작이 바뀌지 않았음을 자동 테스트와 Release 실기기 측정으로 확인한다.
- 검증된 소스 커밋과 Universal 미서명 ZIP, SHA-256, manifest 및 GitHub Pre-release를 일치시킨다.

## 범위

- 앱 마케팅 버전 `1.3.2`, 빌드 번호 `7`과 버전 테스트
- 이동 tick Timer 재사용, 화면·이동 범위 cache와 포인터 기능 수요 기반 30Hz 감시
- 전체 단위 테스트, Debug·Universal Release 빌드와 실제 Preview 앱 스모크 QA
- 미서명·미공증 Preview ZIP, 체크섬, manifest와 GitHub Pre-release 게시·원격 재검증
- 공개 다운로드 인계와 플랫폼 현황 문서 갱신

## 제외 범위

- 이동 주기·속도·애니메이션 또는 사용자 동작 변경
- Developer ID 코드 서명, Apple 공증과 DMG
- Windows 소스 변경·빌드·실제 QA
- 업데이트 확인·자동 업데이트
- `.monglepet` schema와 공통 fixture 변경

## 열린 질문

- 없음

## 결정사항

- 기존 공개 `1.3.1` 뒤의 내부 성능 보정이므로 SemVer patch를 올려 `1.3.2 (7)`로 게시한다.
- 태그는 `macos-v1.3.2-preview.1`, 릴리스 이름은 `MonglePet macOS 1.3.2 Preview 1`로 한다.
- 기존 `1.3.1` 자산과 태그는 수정하지 않고 새 릴리스에 ZIP·SHA-256·manifest를 게시한다.
- 릴리스 태그는 manifest에 기록된 깨끗한 원격 소스 커밋을 가리킨다.

## 작업 순서

### 공통 계약

- [x] 1단계: 변경이 macOS 네이티브 런타임 내부 보정이며 공통 schema·fixture 변경이 없음을 확인한다.

### macOS

- [x] 2단계: 앱 버전과 버전 테스트를 `1.3.2 (7)`로 올린다.
- [x] 3단계: 전체 단위 테스트, Debug 빌드와 기존 Release 성능 회귀를 확인한다.
- [ ] 4단계: 깨끗한 원격 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성하고 압축 해제본을 검증한다.
- [ ] 5단계: GitHub Pre-release를 게시하고 원격 자산과 태그 대상을 다시 검증한다.

### Windows

- [x] 6단계: Windows 소스 변경이 필요 없는 플랫폼 내부 성능 보정임을 인계에 기록한다.

### 플랫폼 동등성

- [ ] 7단계: macOS 배포 결과와 검증 수치를 플랫폼 현황·다운로드 인계 문서에 기록한다.

## 검증 방법

- 전체 `MonglePetTests`와 코드서명 없는 Debug 빌드를 실행한다.
- 기존 `1.3.1 (6)`과 변경 Release 앱을 같은 workload로 비교하고 이동 cadence·시각 동작 불변을 확인한다.
- Preview 스크립트의 Universal Release 빌드와 ZIP 자체 체크섬 검증을 통과한다.
- 별도 임시 디렉터리에 ZIP을 풀어 버전·빌드·Bundle ID·arm64/x86_64와 실제 앱 실행을 확인한다.
- GitHub 릴리스의 세 자산 이름·크기·digest와 태그 대상 커밋을 로컬 최종본과 비교한다.

## 진행 로그

- 2026-08-25: 원격 `main`과 로컬 기준이 일치하고 `macos-v1.3.2-preview.1` 태그·릴리스가 없으며 GitHub 인증이 유효함을 확인했다.
- 2026-08-25: 앱 버전 `1.3.2 (7)`, 태그 `macos-v1.3.2-preview.1`, 릴리스 이름 `MonglePet macOS 1.3.2 Preview 1`로 확정했다.
- 2026-08-25: 성능 기준선·변경본 비교와 세부 수치는 `2026-08-13-multi-pet-runtime.md`의 9A단계 진행 로그에 기록했다.
- 2026-08-25: 버전 반영 뒤 전체 `MonglePetTests` 472개 중 471개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 코드서명 없는 Debug 빌드를 확인했다.
