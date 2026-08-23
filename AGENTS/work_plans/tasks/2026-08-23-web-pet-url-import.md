# 웹 펫 URL 가져오기

## 상태

- 상태: in_progress
- 생성일: 2026-08-23
- 마지막 갱신: 2026-08-24

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
- Windows 순수 C# URL·API 계약과 임시 다운로드 adapter
- Windows packaged MSIX·unpackaged EXE protocol 등록과 공통 요청 router
- 현재 멀티펫의 선택 인스턴스 경계를 유지하는 WinUI 보관함 UI와 기존 로컬 검토·중복·내보내기 재사용
- Windows 단위 테스트, Debug·Release 빌드와 실제 protocol·보관함 QA
- 공통 명세, 웹·Windows 인계와 플랫폼 상태 갱신

## 제외 범위

- 웹 저장소와 서버 API 변경
- 로그인 사용자 전용 펫 또는 비공개 펫 다운로드
- opaque 다운로드 URL의 직접 입력·저장·재사용
- 백그라운드 자동 설치와 사용자 검토 생략
- Windows 스프라이트 순서·crop·450ms 편집 동등성
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
- Windows에서 `현재 펫`은 schema-v11의 `selectedPetInstanceID`가 가리키는 선택 인스턴스로 해석한다. 다운로드와 검토만으로는 어떤 인스턴스나 설정도 바꾸지 않고, 사용자가 설치를 확정한 뒤에만 기존 로컬 가져오기와 같은 선택 인스턴스 교체 경계를 사용한다.
- packaged·unpackaged 활성화는 같은 순수 요청 parser/router를 사용하며, 실행 중 두 번째 요청은 기존 앱 인스턴스로 전달한다. `--startup` 자동 실행은 URL 요청과 별도로 유지한다.
- unpackaged 제거는 현재 protocol 명령이 제거 대상 EXE를 가리킬 때만 현재 사용자 등록을 삭제하며 packaged 연결은 수정하지 않는다.
- 검증된 다운로드는 검토·중복 선택 전체를 소유하는 일회성 임시 세션으로 관리하고 취소·성공·실패의 모든 종단에서 제거한다.
- Windows 변경은 `codex/windows-web-pet-import` 브랜치에서 검증하며 사용자 확인 전 버전 상승·Release 게시·`main` 직접 push를 하지 않는다.

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
- [x] 6-1단계: 순수 C# URL parser, 환경·API envelope·metadata·오류 모델과 테스트를 구현한다.
- [x] 6-2단계: `HttpClient` 다운로드, redirect·크기·SHA-256 검증과 임시 세션 adapter를 구현한다.
- [x] 6-3단계: packaged·unpackaged protocol 등록과 실행 중·종료 상태 공통 요청 router를 구현한다.
- [x] 6-4단계: 최신 macOS 정보 구조에 맞춰 WinUI 펫 보관함을 개편하고 기존 검토·중복·내보내기를 연결한다.
- [x] 6-5단계: Windows 관련 테스트, Debug·Release 전체 빌드·테스트와 실제 앱 QA를 완료한다.

### 플랫폼 동등성

- [ ] 7단계: Windows 구현 후 같은 개발·운영 URL과 패키지 검증 시나리오를 확인한다.

## 검증 방법

- 개발·운영 상세 URL과 custom scheme 정상·거부 사례를 단위 테스트한다.
- 성공·오류 envelope, metadata 불일치, 크기 초과, SHA-256 불일치를 가짜 transport로 검증한다.
- 관련 XCTest부터 전체 `MonglePetTests`, 서명 없는 Debug 빌드로 확장한다.
- 실제 개발 상세 URL을 붙여 넣고 검토 화면, 설치·중복 취소와 임시 파일 정리를 확인한다.
- 앱 종료 상태와 실행 중 상태에서 custom scheme이 설정의 같은 검토 화면을 여는지 확인한다.
- Windows에서는 순수 계약 테스트부터 Packages·Shell·WinUI 관련 테스트, 전체 Debug·Release 빌드·테스트로 확장한다.
- packaged manifest와 unpackaged installer 등록·제거, 두 설치 채널 공존, 실행 중 두 번째 protocol 요청과 `--startup` 회귀를 확인한다.
- 선택 인스턴스 외의 활성 펫·프로필·overlay가 다운로드·취소·오류와 설치 확정 뒤에도 의도하지 않게 바뀌지 않는지 확인한다.

## 진행 로그

- 2026-08-23: 실제 개발 상세 페이지·상세 API·OpenAPI와 다운로드 API 응답을 검토했다.
- 2026-08-23: 웹 상세 URL을 안정적인 사용자 입력으로 두고 매 요청마다 대표 버전 UUID로 짧은 수명 다운로드 URL을 발급받는 계약을 확정했다.
- 2026-08-23: macOS URL 파서·ephemeral API client·20MiB/크기/SHA-256/최소 버전 검증, 설정 입력 UI와 custom scheme을 구현했다.
- 2026-08-23: URL 가져오기 XCTest 10개와 전체 `MonglePetTests`, 서명 없는 Debug 빌드가 통과했다. 외부 fixture가 필요한 기존 Codex WebP 테스트 1개는 조건에 따라 skip됐다.
- 2026-08-23: 실제 개발 상세 URL로 실행 중 앱과 종료 상태 앱 모두 기존 `가져오기 내용 확인` 화면까지 도달함을 확인했다. 종료 상태에서 초기 요청을 놓치던 화면 전환 결함을 발견해 최초 표시 동기화를 추가한 뒤 재검증했다.
- 2026-08-23: 웹 URL, Mac의 로컬 패키지, 현재 펫 내보내기를 독립된 설정 섹션으로 분리하고 Debug에서는 개발 웹·Release에서는 운영 웹을 여는 `펫 보러가기`, 세로 주소 입력, 진행 상태와 인라인 오류·재시도 안내를 추가했다. 웹 저장소 전달 프롬프트에도 custom scheme과 미설치 fallback 계약을 반영했다.
- 2026-08-23: 운영 펫 목록을 `https://mapleroom.kr/monglepet/pets`, 운영 API를 `https://api.mapleroom.kr/api/v1`로 확정하고 Debug·Release의 `펫 보러가기`도 각 환경의 `/monglepet/pets` 목록으로 맞췄다.
- 2026-08-23: 웹 가져오기에서 `펫 보러가기`를 전체 폭 버튼으로 분리하고 구분선 아래에 `주소로 직접 가져오기` 텍스트 필드와 가져오기·재시도 동작을 배치해 두 경로가 한 작업처럼 보이지 않게 정리했다.
- 2026-08-23: URL처럼 보이던 주소 입력 placeholder를 `펫 상세 주소를 붙여 넣으세요`로 바꾸고, 현재 macOS의 세로 섹션 순서·문구·버튼 위계·인라인 오류와 Windows packaged/unpackaged protocol·자동 테스트·실제 QA를 `AGENTS/guides/WINDOWS_WEB_PET_IMPORT_HANDOFF.md`에 구체적으로 인계했다.
- 2026-08-23: Windows `a37bffc` 기준에서 웹 가져오기 구현이 아직 없고, schema-v11 멀티펫·MSIX와 unpackaged EXE·`--startup`·기존 로컬 검토 흐름이 현재 통합 경계임을 확인했다. Windows 구현은 스프라이트 편집 후속과 분리한 `codex/windows-web-pet-import` 브랜치에서 시작했다.
- 2026-08-24: Windows 순수 C#에 개발·운영 상세 URL allowlist, 정확한 deep link query, API envelope·최소 버전·metadata 비교, same-origin HTTPS redirect, 20MiB·실제 크기·SHA-256 검증과 검토 전체를 소유하는 임시 세션을 구현했다. malformed success envelope와 길이를 알 수 없는 20MiB 초과 stream을 포함한 PetLibrary 테스트 63개가 통과했다.
- 2026-08-24: WinUI `펫 보관함`을 웹 탐색·주소 직접 가져오기·Windows 로컬 패키지·현재 펫 내보내기의 세로 섹션으로 정리하고 기존 검토·중복·선택 인스턴스 교체 경계를 재사용했다. 다운로드·검토·취소만으로는 라이브러리와 선택 인스턴스를 바꾸지 않는다.
- 2026-08-24: MSIX manifest와 Inno Setup 현재 사용자 protocol 등록을 추가했다. unpackaged 실행 중 두 번째 요청은 AppInstance 단일 인스턴스를 유지하면서 기존 notification area HWND에 제한된 `WM_COPYDATA` payload로 전달한다. Windows Shell이 `monglepet://install/?...`로 정규화하는 한 개의 slash만 Windows 경계에서 계약형으로 되돌리고 공통 parser는 다른 path를 계속 거부한다.
- 2026-08-24: 실제 개발 펫 `monglepet-0fb1dbc731ce`로 unpackaged 종료·실행 중 deep link가 같은 `가져오기 검토` 화면을 열고 설치·취소 선택을 제공함을 확인했다. 두 경로 모두 취소 후 라이브러리가 바뀌지 않고 `MonglePetRemoteImport-*`가 0개임을 확인했으며 QA protocol 등록과 프로세스를 제거했다.
- 2026-08-24: Debug·Release 전체 빌드와 각 234개 테스트가 통과했다. NuGet 취약성 metadata endpoint 조회 `NU1900` 경고 3개만 남았으며 복원 자체는 성공했다. 기존 동일 버전 loose 개발 패키지는 Windows가 manifest 재등록을 `0x80073CFB`로 차단해 packaged 실제 protocol QA는 아직 완료하지 않았다.
- 2026-08-24: Inno Setup 6.7.3으로 현재 self-contained publish를 다시 압축해 protocol Registry와 조건부 제거 Code를 포함한 설치기 문법 검증을 통과했다. 임시 QA 설치기 63,884,003 bytes는 검증 직후 제거했다.
- 2026-08-24: 버전을 `1.2.0.13`으로 올린 Release 개발 MSIX를 기존 `1.1.0.13` 위에 등록 업데이트했다. LocalState 22개 파일의 크기·SHA-256 차이가 0개였고, 실제 packaged `monglepet://install?...`이 `가져오기 검토`와 설치·취소 버튼을 열었다. 취소 뒤 라이브러리 21개 파일 차이와 임시 폴더가 모두 0개였다.
- 2026-08-24: 버전 정렬 계약 테스트를 추가한 뒤 Debug·Release 전체 빌드와 각 235개 테스트가 다시 통과했다. 코드 오류는 없고 NuGet 취약성 metadata 조회 `NU1900` 경고 3개만 남았다.

## 완료 결과

- macOS 기준 구현과 실제 개발 URL QA, 공통 규격·웹·Windows 인계를 완료했다.
- Windows 구현, unpackaged 실제 개발 URL QA와 Debug·Release 자동 검증을 완료했다.
- 운영 URL, 실제 설치·중복·교차 내보내기와 접근성·혼합 DPI QA가 남아 있어 플랫폼 동등 완료로 표시하지 않는다.

## 남은 위험 / 후속 작업

- 웹의 `MonglePet에서 열기` 링크와 앱 미설치 fallback 반영은 웹 저장소 후속 작업이다.
- 운영 URL, 실제 설치·중복 교체·별도 설치, Windows→macOS 내보내기 왕복, Narrator와 100%·150%·200% DPI는 후속 실제 QA다.
