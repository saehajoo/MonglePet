# Windows 설정 저장과 펫 라이브러리 관리 UI

## 상태

- 상태: done
- 생성일: 2026-08-08
- 마지막 갱신: 2026-08-08

## 목표

- MSIX `LocalState\MonglePet\settings.json`에 선택한 설치 UUID를 schema-v10 JSON으로 안전하게 저장한다.
- 앱 시작 시 저장한 설치를 우선 복원하고 설치가 사라졌으면 안전한 대상을 선택해 설정을 정리한다.
- `.monglepet` 파일 선택 가져오기와 설치 목록의 활성화·삭제를 Windows 개발 UI에서 제공한다.

## 범위

- 순수 C# `MonglePet.Settings` 프로젝트와 xUnit 테스트 프로젝트
- schema-v10 기본 문서, 기존 v10 나머지 필드 보존, UUID 항목 복구
- 5MiB 제한, 손상 파일 격리, 미래 schema 쓰기 차단, 같은 볼륨 임시 파일과 원자적 교체
- 선택 설치 UUID의 시작 복원·전환·삭제 fallback 동기화
- WinUI 파일 선택기, 설치 목록, 활성화와 확인 후 삭제
- Debug·Release 빌드와 실제 packaged 앱 QA

## 제외 범위

- macOS schema-v1부터 v9까지의 전체 행동·이동·말풍선 필드 마이그레이션
- 행동 프로필 편집 UI와 Windows 화면 좌표·자동 규칙 저장
- 펫 패키지 편집·내보내기와 권장 프로필 적용
- 실제 WebP·다중 프레임 신규 fixture 제작

## 열린 질문

- 없음. Windows 신규 저장은 schema-v10으로 시작하고 기존 schema-v10의 미사용 필드는 JSON 원본 구조를 보존한다.

## 결정사항

- 설정 경로는 D-064의 `ApplicationData.Current.LocalFolder\MonglePet\settings.json`을 사용한다.
- 미래 schema는 원본을 보존하고 영구 선택 변경을 차단한다.
- 손상되거나 5MiB를 넘는 파일은 `settings.corrupt-<UUID>.json`으로 이동한 뒤 기본값을 사용한다.
- 삭제 대상이 현재 펫이면 남은 첫 설치로 전환하고, 없으면 bundled 샘플로 돌아간 뒤 선택 UUID를 `null`로 저장한다.

## 작업 순서

- [x] 1단계: Settings 저장 모델·경로·원자적 store 구현
- [x] 2단계: 기본값·왕복·보존·격리·미래 schema·원자성 테스트
- [x] 3단계: App 시작 복원과 활성 설치 설정 동기화
- [x] 4단계: 파일 선택 가져오기·설치 목록 활성화·삭제 UI
- [x] 5단계: Debug·Release 검증, 실제 packaged 앱 QA와 문서 갱신

## 검증 방법

- 임시 디렉터리에서 누락 파일 기본값과 schema-v10 저장 왕복
- 선택 UUID 변경 시 미사용 JSON 필드 보존
- 잘못된 UUID 항목 복구, 손상·초과 크기 격리, 미래 schema 원본 보존과 쓰기 차단
- 기존 설정 교체 후 임시 파일이 남지 않는지 확인
- 실제 packaged 앱에서 가져오기·전환·재시작 복원·삭제 fallback 확인
- Debug·Release 전체 빌드와 전체 xUnit, `git diff --check`

## 진행 로그

- 2026-08-08: `SETTINGS_SCHEMA.md`, macOS `AppSettingsStore`, Windows 앱·PetLibrary 경계를 확인했다. Windows가 아직 사용하지 않는 v10 필드는 재직렬화로 유실하지 않고 JSON 문서를 보존하면서 선택 UUID만 갱신한다.
- 2026-08-08: 순수 C# Settings 프로젝트에 schema-v10 기본 문서, 5MiB 제한, 손상 격리, 과거·미래 schema 보호와 같은 볼륨 임시 파일 overwrite rename을 구현하고 대상 테스트 9개를 통과했다.
- 2026-08-08: 앱 시작 선택 복원, 활성화·가져오기·삭제 설정 동기화와 WinUI 파일 선택기·중복 교체/별도 설치·설치 목록 관리 UI를 연결했다.
- 2026-08-08: 실제 packaged Debug 앱에서 누락 선택 UUID를 설치 UUID로 복구하고 미사용 JSON marker 보존·임시 파일 0개를 확인했다. 재실행은 수정 시각 변경 없이 같은 UUID를 복원했고, 설치 제거 후에는 `null`과 bundled 샘플로 복구했다.
- 2026-08-08: 최종 Debug·Release 전체 빌드가 경고·오류 없이 통과했고 총 44개 xUnit 테스트가 두 구성에서 모두 통과했다. Release packaged 앱 시작을 확인한 뒤 프로세스·개발 MSIX·QA 데이터를 제거했다.

## 완료 결과

- schema-v10 선택 설치 UUID 저장과 시작 복원, 손상·초과 크기 격리, 미사용 필드 보존과 원자적 교체를 구현했다.
- `.monglepet` 파일 선택 가져오기, 중복 교체·별도 설치, 설치 목록 활성화·확인 후 삭제 개발 UI를 구현했다.
- 실제 LocalState 복구·재시작·설치 없음 fallback과 Debug·Release 44개 테스트를 통과했다.

## 남은 위험 / 후속 작업

- Windows가 행동·화면 설정을 사용하기 시작할 때 schema-v1~v9 전체 마이그레이션과 타입 매핑을 별도 작업으로 추가한다.
- OS 파일 선택 대화상자의 실제 파일 선택과 중복 선택 ContentDialog는 대화형 데스크톱에서 수동 QA한다.
- 가져오기 전 상세 검토, 권장 프로필 적용과 `.monglepet` 내보내기는 후속 작업이다.
