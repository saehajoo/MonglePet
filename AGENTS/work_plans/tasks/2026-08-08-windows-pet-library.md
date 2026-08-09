# Windows 로컬 펫 라이브러리와 실행 중 전환

## 상태

- 상태: done
- 생성일: 2026-08-08
- 마지막 갱신: 2026-08-08

## 목표

- 검증된 `.monglepet` 패키지를 MSIX `LocalState\MonglePet\Library\<installation-uuid>`에 안전하게 설치한다.
- 같은 패키지 ID의 중복 설치·별도 설치·기존 설치 교체를 명시적으로 처리한다.
- Windows 앱에서 설치 목록을 확인하고 설치된 펫으로 오버레이를 전환할 수 있는 최소 개발 UI를 만든다.

## 범위

- 순수 C# `MonglePet.PetLibrary` 프로젝트와 xUnit 테스트 프로젝트
- 디렉터리·ZIP 입력의 임시 준비, 전체 재검증과 같은 볼륨 staging 설치
- 설치 UUID 목록, 중복 거부, 별도 사본 설치, 같은 패키지 ID 교체, 삭제
- 교체 실패 시 기존 설치 복구와 숨은 staging·backup 무시
- bundled 공통 샘플 설치와 실행 중 오버레이 전환 개발 UI
- 플랫폼 동등성·로드맵·Windows 문서 갱신

## 제외 범위

- 전체 설정 schema-v10과 선택 펫 재실행 복원
- 시스템 파일 선택기와 가져오기 검토 화면
- 펫 편집·내보내기와 권장 프로필 적용
- 실제 WebP 원본 fixture 생성 또는 이미지 변환
- 다중 프레임 시각 자산 제작, 이동·말풍선·시스템 트레이

## 열린 질문

- 실제 정적 알파 WebP와 시각적으로 구분되는 다중 프레임 공통 fixture는 자산 출처와 게시 권한을 확인한 뒤 별도 추가한다.

## 결정사항

- 설치 루트는 D-064에 따라 `ApplicationData.Current.LocalFolder\MonglePet\Library`를 사용한다.
- 설치 디렉터리 이름은 패키지 ID와 분리된 UUID이며 같은 패키지 ID의 별도 사본을 허용한다.
- 입력 원본을 직접 재생하지 않고 라이브러리와 같은 볼륨의 staging 사본을 전체 재검증한 뒤 최종 UUID 경로로 rename한다.
- 교체는 같은 패키지 ID에만 허용하고 기존 디렉터리를 backup으로 rename한 뒤 새 staging을 적용한다.

## 작업 순서

- [x] 1단계: PetLibrary 프로젝트·설치 모델·오류 모델 생성
- [x] 2단계: 디렉터리·ZIP importer와 원자적 store 구현
- [x] 3단계: 중복·별도 설치·교체·복구·삭제 xUnit 테스트
- [x] 4단계: bundled 샘플 설치·목록·오버레이 전환 개발 UI 연결
- [x] 5단계: Debug·Release 빌드, 실제 packaged 앱 QA와 문서 갱신

## 검증 방법

- 임시 라이브러리 루트에서 정상 디렉터리·ZIP 설치와 재로딩
- 고정 UUID 생성기로 최종 경로와 중복 설치 결과 검증
- 다른 패키지 ID 교체 거부, 손상 staging 실패 시 기존 설치 보존
- 숨은 staging·backup과 손상 설치를 목록에서 제외
- bundled 샘플 설치 후 실제 packaged 앱 접근성 상태와 overlay package 이름 확인
- `dotnet build` Debug·Release, 전체 xUnit, `git diff --check`

## 진행 로그

- 2026-08-08: 공통 명세와 macOS `PetLibraryStore`·`PetPackageInstaller` 경계를 확인했다. 저장소에는 실제 WebP fixture가 없으므로 이 작업에서 비정상 합성 자산을 만들지 않고 라이브러리 설치 경계를 우선 구현한다.
- 2026-08-08: 실제 packaged 앱에서 일반 `%LOCALAPPDATA%` 쓰기가 package `LocalCache`로 가상화되는 것을 확인했다. 제한 capability로 가상화를 해제하지 않고 표준 `ApplicationData.Current.LocalFolder`의 `LocalState`를 사용하도록 D-064로 저장 루트를 보정했다.
- 2026-08-08: `MonglePet.PetLibrary`와 테스트 프로젝트를 추가하고 디렉터리·ZIP import, UUID 설치, 중복·별도 설치·교체·rollback·삭제, 손상·숨은 작업 디렉터리 제외를 구현했다.
- 2026-08-08: 개발 UI에서 bundled 공통 샘플을 설치하고 오버레이를 즉시 전환했다. 실제 packaged Debug 앱 재시작과 Release 앱에서 동일 설치 UUID와 `LocalState` 경로가 복원되는 것을 확인했다.
- 2026-08-08: Debug·Release 전체 솔루션 빌드가 경고·오류 없이 통과했고 Core 8개, Packages 17개, PetLibrary 10개로 총 35개 xUnit 테스트가 두 구성에서 모두 통과했다. QA용 프로세스·개발 패키지·패키지 데이터는 검증 후 제거했다.

## 완료 결과

- MSIX `LocalState\MonglePet\Library`에 원자적 UUID 펫 라이브러리를 구현했다.
- bundled 공통 샘플의 설치·기존 중복 활성화·실행 중 오버레이 전환·재시작 복원을 실제 packaged 앱에서 검증했다.
- Debug·Release 빌드와 총 35개 자동 테스트를 통과했고 문서·기능 동등성 현황을 갱신했다.

## 남은 위험 / 후속 작업

- 실제 WebP·다중 프레임 공통 fixture와 Windows 이미지 디코더 실제 QA가 필요하다.
- 설정 schema와 선택 설치 UUID의 명시적 복원은 다음 Windows 설정 저장 작업에서 연결한다.
- 파일 선택기·가져오기 검토 화면과 전체 설치 관리 UI는 후속 작업이다.
