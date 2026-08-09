# Windows 설정 schema-v1~v9 마이그레이션

## 상태

- 상태: completed
- 생성일: 2026-08-08
- 마지막 갱신: 2026-08-08

## 목표

- Windows `AppSettingsStore`가 schema-v1부터 v9까지 순차 변환해 schema-v10으로 원자적으로 교체한다.
- v1 행동 단계의 유지 시간을 선택 펫 manifest의 모션 한 사이클 시간으로 반복 횟수에 변환한다.
- 이전 설정의 선택 UUID와 사용자 필드를 유지하면서 버전별 새 기본 필드만 추가한다.

## 범위

- JSON 기반 v1→v2→…→v10 순차 migrator
- v1 모션 주기 해석 delegate와 Windows PetLibrary·bundled 패키지 adapter
- v3 이동 기본값, v4 표시 환경, v5 방향 이동, v6 도망가기, v7~v10 말풍선 필드 변환
- 이전 schema 원자적 재작성과 migration source·issue 보고
- schema-v1 fixture 및 v2~v9 시작 버전별 xUnit 테스트
- Debug·Release 전체 검증과 문서 갱신

## 제외 범위

- Windows 설정 UI에서 행동·이동·말풍선 필드 편집
- Windows 화면 좌표와 macOS 화면 식별자의 런타임 적용
- 현재 schema-v10의 전체 항목 단위 유효성 복구 mapper
- 새로운 schema-v11 설계

## 열린 질문

- 없음

## 결정사항

- migrator는 버전마다 하나의 작은 구조 변환을 적용하고 모든 변환이 성공한 뒤에만 v10 파일을 overwrite rename한다.
- v1에서 모션을 찾지 못하거나 주기 합계를 계산할 수 없으면 `__monglepet_current_pet_default__`, 반복 1회로 복구한다.
- 선택 설치를 찾지 못하는 v1 파일은 명세에 따라 원본을 유지하고 쓰기를 차단한다. 선택 펫 정의는 있지만 개별 모션을 찾지 못한 경우에만 안전 fallback을 사용한다.
- 미래 schema는 계속 원본을 보존하고 쓰기를 차단한다.

## 작업 순서

- [x] 1단계: 순차 JSON migrator와 migration 결과 모델 구현
- [x] 2단계: schema-v1 모션 주기 adapter를 Windows 앱에 연결
- [x] 3단계: v1 fixture와 v2~v9 시작 버전 회귀 테스트
- [x] 4단계: Debug·Release 전체 빌드·테스트와 packaged 앱 실제 migration QA
- [x] 5단계: 설정 명세·동등성·테스트 문서 갱신

## 검증 방법

- macOS v1 fixture의 focus·기본·누락 모션 반복 횟수 변환 비교
- v2부터 v9까지 각 시작 버전을 v10으로 승격하고 단계별 기본 필드 확인
- 선택 UUID와 기존 overlay·profile·speech 사용자 값 보존
- 변환 후 임시 파일 없음, 재로드 시 추가 쓰기 없음, 미래 schema 원본 보존
- Debug·Release 전체 빌드와 전체 xUnit, 실제 packaged LocalState migration

## 진행 로그

- 2026-08-08: `SETTINGS_SCHEMA.md`와 macOS `StoredAppSettingsV2`~`V10` migrator를 대조했다. v1만 펫 정의 의존성이 있고 v2 이후는 순수 JSON 구조 변환으로 분리할 수 있음을 확인했다.
- 2026-08-08: `AppSettingsMigrator`에 v1→v2→…→v10 구조 변환을 구현하고, 앱에서 선택 설치 또는 bundled manifest의 프레임 시간을 합산하는 adapter를 연결했다.
- 2026-08-08: 마이그레이션 직전 입력 stream이 열려 있어 Windows overwrite가 거부되는 문제를 테스트에서 발견해, JSON 파싱 직후 stream을 닫고 원자적 교체하도록 수정했다.
- 2026-08-08: macOS v1 fixture와 v2~v9 각 시작 버전 테스트를 추가했다. 선택 펫 정의 누락 시 v1 원본과 쓰기 차단을 유지하고 미래 schema 보호가 회귀하지 않는 것도 확인했다.
- 2026-08-08: 실제 packaged Debug `LocalState`에서 v1 fixture를 v10으로 변환해 반복 횟수 3·2·1, 새 이동·말풍선 기본값, 임시 파일 0개와 앱 정상 응답을 확인했다. 재로드 무재작성은 단위 테스트로 확인했다.
- 2026-08-08: x64 Debug·Release 빌드가 경고·오류 없이 통과했고 Core 8개, Packages 17개, PetLibrary 10개, Settings 19개로 총 54개 테스트가 두 구성에서 모두 통과했다.

## 완료 결과

- schema-v1부터 v9까지의 Windows 순차 마이그레이션과 v10 원자적 교체를 완료했다.
- v1은 실제 선택 펫 manifest의 모션 사이클로 반복 횟수를 계산하고, 모션만 누락된 경우 현재 펫 기본 모션 1회로 복구한다.
- 선택 펫 정의가 없는 v1과 미래 schema는 원본을 보존하고 설정 쓰기를 차단한다.

## 남은 위험 / 후속 작업

- schema-v10 전체 필드의 Windows Domain 타입 매핑과 항목 단위 복구는 후속 설정 기능 작업에서 구현한다.
