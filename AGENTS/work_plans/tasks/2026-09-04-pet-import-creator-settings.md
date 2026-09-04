# 펫 가져오기 제작자 설정 자동 적용

## 상태

- 상태: in_progress
- 생성일: 2026-09-04
- 마지막 갱신: 2026-09-04

## 목표

- 로컬 파일과 웹 URL 가져오기에서 기본 설정·권장 설정 선택을 제거하고 하나의 `펫 추가` 작업으로 통합한다.
- 유효한 제작자 설정은 새 펫의 독립 설정에 자동 적용하고, 없거나 적용할 수 없으면 안전한 최소 프로필로 추가한다.
- 기존 펫과 전역 설정, 패키지 보안 경계 및 원자적 rollback을 보존한다.
- macOS에서 확정한 결과를 공통 명세와 Windows 후속 구현 문서에 전달한다.

## 범위

- `.monglepet` 가져오기 시 제작자 설정 적용 정책과 사용자 용어
- macOS `PetLibrarySession`의 검토 완료 설치 경계와 결과 안내
- macOS 로컬·웹 공통 가져오기 검토 화면
- 자동 적용·최소 프로필 fallback·독립성·rollback 회귀 테스트
- 패키지·설정 명세, 제품 결정, 플랫폼 동등성 및 Windows 인계

## 제외 범위

- `.monglepet` formatVersion, 로컬 settings schema-v15와 권장 프로필 schema-v11 변경
- `recommended-profile.json` 파일명과 codec의 내부 기술 명칭 변경
- 패키지 보안 제한 완화
- Windows 소스 구현·빌드·실제 QA

## 열린 질문

- 없음

## 결정사항

- 가져오기 검토는 정보 확인만 제공하고 제작자 설정 적용 여부를 선택하게 하지 않는다.
- 유효한 제작자 설정은 새 installation·instance·profile의 휴대 가능한 행동·이동·말풍선·표시 설정에 자동 적용한다.
- 제작자 설정이 없으면 새 펫용 안전한 최소 프로필을 사용한다.
- 제작자 설정이 미래 schema이거나 손상되었지만 패키지 자체가 유효하면 최소 프로필로 추가하고 적용하지 못했다는 성공 안내를 표시한다.
- 1 MiB 제한 초과, 실행 파일, 경로 탈출, 자산 손상과 지원하지 않는 패키지 형식 등 기존 보안 실패는 계속 전체 가져오기를 차단한다.
- 같은 펫의 반복 가져오기는 각각 독립 installation·instance·profile을 만든다.
- 사용자 실제 확인 뒤 macOS 앱은 `1.6.0 (14)`, 태그 `macos-v1.6.0-preview.3`의 미서명·미공증 Preview ZIP으로 게시한다.

## 작업 순서

### 공통 계약

- [x] D-118에 단일 `펫 추가`와 제작자 설정 자동 적용·fallback 정책을 기록한다.
- [x] `PET_PACKAGE.md`와 `SETTINGS_SCHEMA.md`의 선택형 적용 문구를 새 정책으로 바꾼다.

### macOS

- [x] 검토 완료 설치 API에서 사용자 선택 인자를 제거하고 검토된 제작자 설정을 자동 전달한다.
- [x] 미래·손상 제작자 설정 fallback 성공을 오류와 구분해 안내한다.
- [x] 가져오기 검토 화면을 정보용 제작자 설정 요약과 단일 `펫 추가` 버튼으로 바꾼다.
- [x] 로컬 파일과 웹 URL 흐름이 같은 설치 정책과 임시 파일 정리 경계를 사용하는지 검증한다.
- [x] 관련 단위·가져오기 테스트와 전체 macOS 단위 테스트를 통과한다.
- [x] Debug 빌드와 `git diff --check`를 통과한다.
- [x] 실제 macOS 앱 QA를 완료한다.

### macOS Preview 3 릴리스

- [x] 앱 버전과 버전 테스트를 `1.6.0 (14)`로 올린다.
- [x] 최종 전체 단위 테스트와 Debug 빌드를 통과한다.
- [x] 소스·명세·버전 변경을 커밋하고 `origin/main`에 푸시한다.
- [x] 깨끗한 원격 커밋에서 Universal Preview ZIP·SHA-256·manifest를 생성한다.
- [x] `macos-v1.6.0-preview.3` GitHub Pre-release를 게시한다.
- [x] 원격 태그 대상과 세 자산의 크기·digest를 재검증한다.
- [x] 배포 문서·다운로드 인계·플랫폼 현황에 최종 결과를 기록하고 푸시한다.

### Windows

- [x] Windows 인계 문서에 Domain·저장·WinUI 변경, 제외 범위와 필수 검증을 기록한다.
- [ ] Windows 환경에서 단일 추가 UI와 자동 적용·fallback을 네이티브로 구현한다.
- [ ] Windows 자동 테스트와 실제 앱 QA를 완료한다.

### 플랫폼 동등성

- [ ] 유효·없음·미래·손상 제작자 설정 패키지를 두 플랫폼에서 같은 결과로 가져온다.
- [ ] 같은 패키지 반복 추가의 독립 installation·instance·profile을 비교한다.
- [ ] macOS↔Windows 패키지 교차 왕복 뒤 휴대 설정을 비교한다.

## 검증 방법

- `PetLibrarySessionTests`: 유효 제작자 설정 자동 전달, 없음·손상 fallback, 독립 추가와 settings 실패 rollback
- `PetPackageInstallerTests`: 없음·미래·손상 설정은 검토 가능, 1 MiB와 패키지 보안 실패는 차단
- `AppSettingsSessionTests`: 새 profile·overlay 적용과 기존 인스턴스 독립성·재로드
- macOS 전체 `MonglePetTests`, Debug 빌드, `git diff --check`
- 실제 앱에서 로컬·웹 가져오기 문구, 취소 무변경, 반복 추가와 fallback 성공 안내 확인

## 진행 로그

- 2026-09-04: `main`과 `origin/main`이 `4d5a89c`로 동기화되고 작업 트리가 깨끗함을 확인했다. 기존 코드는 검토 화면에서 기본·권장 적용을 선택하며 두 진입점 모두 `PetLibrarySession.installReviewedPackage`와 동일한 settings 원자 저장·installation rollback 경계를 사용한다.
- 2026-09-04: macOS 로컬 파일·웹 URL 검토 화면을 단일 `펫 추가`로 통합하고 유효한 제작자 설정 자동 적용, 없음·미래·손상 fallback, 별도 성공 안내를 구현했다. 취소 무변경과 settings 저장 실패 rollback을 포함한 회귀 테스트를 보강했다.
- 2026-09-04: macOS 전체 단위 테스트 537개 중 536개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개, Debug 빌드와 `git diff --check`를 통과했다.
- 2026-09-04: D-118, 패키지·설정 명세, 플랫폼 동등성 및 Windows 전용 인계서를 갱신했다. Windows 소스는 변경하지 않았다.
- 2026-09-04: 사용자가 실제 가져오기 동작을 확인하고 릴리스를 요청해 `1.6.0 (14)`, `macos-v1.6.0-preview.3`으로 확정했다.
- 2026-09-04: `1.6.0 (14)` 기준 전체 단위 테스트 537개 중 536개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 Debug 빌드, `git diff --check`를 통과했다.
- 2026-09-04: 사용자 확인에 따라 macOS `선택한 펫` 사이드바의 `행동 편집`을 `펫 정보·애니메이션` 바로 다음으로 옮겼고 Debug 빌드를 통과했다. Windows도 같은 정보 순서로 조정하도록 인계 문서에 추가했다.
- 2026-09-04: 기능·명세·버전 커밋 `26c18f4`와 탐색 순서·Windows 인계 커밋 `b054e35`를 `origin/main`에 푸시했다.
- 2026-09-04: 소스 커밋 `b054e35d6ac3edc7cb18e44461bb8f870a6a40a5`에서 10,890,414 bytes Universal ZIP을 생성했다. SHA-256은 `b555b0fa03b7f95c7d6d545bae929a9269605a2fdcf372a3fd039e5eb4f36ef2`이며 압축 해제본의 `1.6.0 (14)`·Bundle ID·arm64/x86_64·앱 아이콘을 확인했다.
- 2026-09-04: 태그 `macos-v1.6.0-preview.3`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시했다. 원격 태그 대상과 다시 내려받은 세 자산의 바이트 단위 일치·digest를 검증했다.

## 완료 결과

- macOS 구현·자동 검증·Preview 3 배포를 완료했다.
- 실제 macOS 가져오기 동작은 사용자가 확인했다. Windows 구현·교차 왕복은 후속이므로 전체 계획 상태는 `in_progress`를 유지한다.

## 남은 위험 / 후속 작업

- Windows 구현과 macOS↔Windows 실제 교차 왕복 전에는 플랫폼 동등 완료로 표시하지 않는다.
