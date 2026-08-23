# 웹 펫 URL 가져오기

## 상태

- 상태: in_progress
- 생성일: 2026-08-23
- 마지막 갱신: 2026-08-23

## 목표

- 사용자가 MonglePet 웹의 공개 펫 상세 주소를 붙여 넣어 최신 공개 `.monglepet` 패키지를 가져올 수 있게 한다.
- 웹의 `MonglePet에서 열기`가 같은 가져오기 검토 흐름을 시작할 수 있게 macOS custom scheme을 제공한다.
- 짧은 수명의 다운로드 URL을 저장하거나 신뢰하지 않고 API 메타데이터, 크기, SHA-256과 기존 로컬 패키지 검증을 모두 통과한 뒤 설치하게 한다.

## 범위

- 개발·운영 웹 상세 주소의 엄격한 파싱과 API 환경 매핑
- 공개 상세 API와 버전 다운로드 API 조회
- 임시 파일 다운로드, 크기·SHA-256 검증과 수명 관리
- macOS 설정의 URL 입력 UI와 기존 `가져오기 내용 확인`·중복 처리 재사용
- `monglepet://install?url=...` custom scheme 수신
- App Sandbox 발신 네트워크 권한
- 단위 테스트, macOS 빌드와 실제 개발 URL QA
- 공통 명세, 웹·Windows 인계와 플랫폼 상태 갱신

## 제외 범위

- 웹 저장소와 서버 API 변경
- 로그인 사용자 전용 펫 또는 비공개 펫 다운로드
- opaque 다운로드 URL의 직접 입력·저장·재사용
- 백그라운드 자동 설치와 사용자 검토 생략
- Windows 소스 변경·빌드·실제 앱 QA
- 새 내장 펫, 앱 버전 상승과 GitHub Release 게시

## 열린 질문

- 없음. 운영 펫 목록은 `https://mapleroom.kr/monglepet/pets`, 운영 API는 `https://api.mapleroom.kr/api/v1`로 확정했다.

## 결정사항

- 사용자 입력의 단일 원본은 공개 웹 상세 URL이며 개발 `dev.mapleroom.kr`과 운영 `mapleroom.kr`만 허용한다.
- 앱은 상세 응답의 대표 버전 UUID를 사용해 매번 새 다운로드 URL을 발급받는다.
- API가 HTTP 200으로 오류를 반환할 수 있으므로 HTTP 상태와 함께 envelope의 `status`·`code`를 판정한다.
- 다운로드 URL은 해당 환경 API origin의 `/media/monglepet/downloads/` 상대 경로만 허용한다.
- 상세·다운로드 메타데이터의 크기와 SHA-256이 일치해야 하며 20MiB 상한과 실제 SHA-256을 다시 확인한다.
- 검증된 임시 파일은 기존 로컬 패키지 검토·중복 설치 경로로 전달하고 완료·취소 후 제거한다.
- custom scheme은 `monglepet://install?url=<percent-encoded HTTPS detail URL>` 형식이며 다운로드 token은 포함하지 않는다.

## 작업 순서

### 공통 계약

- [x] 1단계: URL·API·보안·임시 파일 수명 계약을 확정한다.

### macOS

- [x] 2단계: URL 파서, API 클라이언트와 다운로드 검증을 구현한다.
- [x] 3단계: 설정 URL 입력과 기존 가져오기 검토 흐름을 연결한다.
- [x] 4단계: custom scheme과 앱 시작·실행 중 요청 전달을 구현한다.
- [x] 5단계: 단위 테스트, 전체 테스트, Debug 빌드와 실제 개발 URL QA를 완료한다.

### Windows

- [x] 6단계: macOS 확정 동작과 Windows 구현·QA 항목을 인계한다.

### 플랫폼 동등성

- [ ] 7단계: Windows 구현 후 같은 개발·운영 URL과 패키지 검증 시나리오를 확인한다.

## 검증 방법

- 개발·운영 상세 URL과 custom scheme 정상·거부 사례를 단위 테스트한다.
- 성공·오류 envelope, metadata 불일치, 크기 초과, SHA-256 불일치를 가짜 transport로 검증한다.
- 관련 XCTest부터 전체 `MonglePetTests`, 서명 없는 Debug 빌드로 확장한다.
- 실제 개발 상세 URL을 붙여 넣고 검토 화면, 설치·중복 취소와 임시 파일 정리를 확인한다.
- 앱 종료 상태와 실행 중 상태에서 custom scheme이 설정의 같은 검토 화면을 여는지 확인한다.

## 진행 로그

- 2026-08-23: 실제 개발 상세 페이지·상세 API·OpenAPI와 다운로드 API 응답을 검토했다.
- 2026-08-23: 웹 상세 URL을 안정적인 사용자 입력으로 두고 매 요청마다 대표 버전 UUID로 짧은 수명 다운로드 URL을 발급받는 계약을 확정했다.
- 2026-08-23: macOS URL 파서·ephemeral API client·20MiB/크기/SHA-256/최소 버전 검증, 설정 입력 UI와 custom scheme을 구현했다.
- 2026-08-23: URL 가져오기 XCTest 10개와 전체 `MonglePetTests`, 서명 없는 Debug 빌드가 통과했다. 외부 fixture가 필요한 기존 Codex WebP 테스트 1개는 조건에 따라 skip됐다.
- 2026-08-23: 실제 개발 상세 URL로 실행 중 앱과 종료 상태 앱 모두 기존 `가져오기 내용 확인` 화면까지 도달함을 확인했다. 종료 상태에서 초기 요청을 놓치던 화면 전환 결함을 발견해 최초 표시 동기화를 추가한 뒤 재검증했다.
- 2026-08-23: 웹 URL, Mac의 로컬 패키지, 현재 펫 내보내기를 독립된 설정 섹션으로 분리하고 Debug에서는 개발 웹·Release에서는 운영 웹을 여는 `펫 보러가기`, 세로 주소 입력, 진행 상태와 인라인 오류·재시도 안내를 추가했다. 웹 저장소 전달 프롬프트에도 custom scheme과 미설치 fallback 계약을 반영했다.
- 2026-08-23: 운영 펫 목록을 `https://mapleroom.kr/monglepet/pets`, 운영 API를 `https://api.mapleroom.kr/api/v1`로 확정하고 Debug·Release의 `펫 보러가기`도 각 환경의 `/monglepet/pets` 목록으로 맞췄다.
- 2026-08-23: 웹 가져오기에서 `펫 보러가기`를 전체 폭 버튼으로 분리하고 구분선 아래에 `주소로 직접 가져오기` 텍스트 필드와 가져오기·재시도 동작을 배치해 두 경로가 한 작업처럼 보이지 않게 정리했다.

## 완료 결과

- macOS 기준 구현과 실제 개발 URL QA, 공통 규격·웹·Windows 인계를 완료했다.
- Windows 구현과 플랫폼 동등성 검증은 Windows 환경의 후속 작업으로 남는다.

## 남은 위험 / 후속 작업

- 웹의 `MonglePet에서 열기` 링크와 앱 미설치 fallback 반영은 웹 저장소 후속 작업이다.
- Windows 구현과 실제 QA 전에는 플랫폼 동등 완료로 표시하지 않는다.
