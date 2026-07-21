# MonglePet 테스트 전략

## 원칙

- 도메인 규칙은 운영체제 API 없이 빠른 단위 테스트로 검증한다.
- 시스템 API와 파일 시스템은 adapter 경계에서 통합 테스트한다.
- UI 테스트는 핵심 사용자 흐름과 앱 실행 가능 여부에 집중한다.
- 코드 변경 후 가장 좁은 관련 테스트부터 실행하고 영향 범위에 따라 검증을 확장한다.
- 시간 기반 로직은 실제 대기 대신 주입 가능한 시계로 검증한다.

## 기본 빌드

```sh
xcodebuild -project MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 단위 테스트

```sh
xcodebuild -project MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:MonglePetTests
```

주요 단위 테스트 대상:

- 자동·수동 모드 우선순위
- 유휴 시간 경계값과 히스테리시스
- 앱 규칙 매칭과 기본 폴백
- 행동 목록 시간 진행과 반복
- Domain `Duration`과 저장 DTO 정수 밀리초 변환
- 명시적인 자동 규칙 조건 JSON discriminator
- 누락된 모션의 `idle` 대체
- 패키지 경로, 크기, 이미지와 manifest 검증
- Codex legacy v1 8×9 및 v2 8×11 WebP atlas 매핑
- 정적 WebP와 animated WebP 판별 및 미지원 형식 거부
- 손상된 설정 복구와 스키마 마이그레이션

## UI 테스트

```sh
xcodebuild -project MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  test -only-testing:MonglePetUITests
```

UI 테스트는 앱 실행과 접근성 자동화가 가능한 macOS 세션에서 실행한다. 기본 스모크 테스트는 앱 실행, 메뉴 막대 항목 또는 펫 창 노출, 핵심 설정 화면 진입 여부를 확인한다.

## 통합 테스트

- 펫 설치와 재실행 후 복원
- 전면 앱 전환에 따른 행동 변경
- 입력 재개 후 휴식·수면 해제
- 화면 잠금·절전에서 렌더링 중지
- 설정 변경의 즉시 반영
- 펫 제거 시 파일과 설정 정리
- 원자적 설정 저장과 손상 파일 복구

## 수동 QA

- 다중 모니터와 화면 배율 변경
- 전체 화면 앱과 여러 Space
- 클릭 통과와 드래그
- 로그인 직후 실행
- 동작 줄이기 설정
- 매우 크거나 잘못된 외부 패키지
- lossless/lossy WebP와 알파가 없는 WebP 가져오기 결과
- 장시간 실행과 절전 복귀

## 성능 검증

- 펫 숨김과 화면 잠금 상태에서 애니메이션 시계가 중지되는지 확인한다.
- 일반 애니메이션 평균 CPU 1% 미만을 초기 목표로 측정한다.
- 설정창을 닫은 뒤 관련 UI 메모리가 해제되는지 확인한다.
- 1시간 실행 후 지속적인 메모리 증가가 없는지 확인한다.
- 이미지 디코딩과 프레임 캐시의 최대 메모리 사용량을 큰 테스트 패키지로 측정한다.

### Phase 1 기준선

- 측정일: 2026-07-21
- 대상: Debug 빌드, 정적 펫 표시 및 사용자 입력이 없는 상태
- 방법: `top`으로 1초 간격 5회 측정
- 결과: CPU 5회 모두 0.0%, 메모리 약 26MB
- 비고: 애니메이션 런타임이 추가되는 Phase 2에서 Instruments로 다시 측정한다.

### Phase 2B 패키지 로더 검증

- 측정일: 2026-07-21
- 실제 PNG 및 정적 WebP fixture로 이미지 형식, 픽셀 크기와 알파 판별 확인
- 경로 탈출, 심볼릭 링크, 스크립트, 누락·중복 참조와 자원 상한 거부 확인
- 패키지 로더 테스트 15개 및 전체 단위 테스트 38개 통과
- 알파 포함 lossless/lossy WebP와 Codex atlas fixture는 Phase 2D에서 추가 검증

### Phase 2C 패키지 설치 검증

- 측정일: 2026-07-21
- 실제 ZIP 생성 후 security-scoped 접근, 임시 추출, 재검증과 UUID 라이브러리 설치 확인
- 경로 탈출, 절대 경로, 심볼릭 링크, 경로 충돌, 손상 ZIP과 압축 폭탄 제한 확인
- 중복 거부, 별도 사본, 같은 패키지 ID 교체와 실패 시 workspace·staging 정리 확인
- 패키지 설치 테스트 10개 및 전체 단위 테스트 48개 통과

### UI 자동화 환경 기록

- 설정창 UI 스모크 테스트는 Phase 1A에서 통과했다.
- Phase 1D 전체 UI 테스트 재실행은 Xcode Runner가 앱과 연결되기 전에 signal kill로 종료되어 완료하지 못했다.
- 설정창, 펫 오버레이, 메뉴 막대, 드래그, 표시 상태 전환과 화면 구성 변경은 실제 앱 수동 QA로 확인했다.

## 변경 유형별 최소 검증

| 변경 유형 | 최소 검증 |
| --- | --- |
| 문서만 변경 | Markdown 링크와 경로 검사 |
| 순수 Domain 변경 | 관련 단위 테스트 |
| 저장·패키지 변경 | 단위 테스트와 임시 디렉터리 통합 테스트 |
| AppKit 창 또는 런타임 변경 | 빌드, 관련 단위 테스트, 수동 실행 |
| SwiftUI 설정 화면 변경 | 빌드와 관련 UI 스모크 테스트 |
| 릴리스 관련 변경 | 전체 테스트, 수동 QA, 성능 기준선 |

---

문서 상태: active
마지막 갱신: 2026-07-21
