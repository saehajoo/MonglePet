# macOS 1.4.0 행동 중심 설정·최종 몽글이 Preview 릴리스

## 상태

- 상태: completed
- 생성일: 2026-08-27
- 마지막 갱신: 2026-08-27

## 목표

- `1.3.2 (7)` 이후 확정한 행동 중심 설정, 이동 방식별 독립 옵션과 편집 흐름을 macOS `1.4.0 (8)` Preview로 게시한다.
- 사용자 제공 최종 몽글이 `1.0.3`과 권장 프로필 v10이 들어간 Universal 앱을 다른 Mac에서 직접 검증할 수 있게 한다.
- 검증된 소스 커밋, 미서명 ZIP, SHA-256, manifest와 GitHub Pre-release를 일치시킨다.

## 범위

- 앱 마케팅 버전 `1.4.0`, 빌드 번호 `8`과 버전 테스트
- schema-v12~v14 행동·설정 마이그레이션과 이동 방식별 독립 값
- 행동 우선순위·랜덤 선택·입력 없음 초 단위·랜덤 머무르기
- 애니메이션 프레임 재사용·변환·복제와 저장 경계·오류 안내
- 내장 몽글이 `1.0.3`, 13개 모션·53프레임과 권장 프로필 v10
- 전체 단위 테스트, Debug·Universal Release 빌드
- 미서명·미공증 Preview ZIP, 체크섬, manifest와 GitHub Pre-release 게시·원격 재검증
- 공개 다운로드 인계와 플랫폼 현황 문서 갱신

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- Windows 소스 변경·빌드·실제 QA
- 앱 내 업데이트 확인과 자동 업데이트
- 실제 다른 Mac의 최종 사용자 QA

## 열린 질문

- 없음

## 결정사항

- 사용자 설정과 제작 흐름이 확장된 기능 릴리스이므로 SemVer minor를 올려 `1.4.0 (8)`로 게시한다.
- 태그는 `macos-v1.4.0-preview.1`, 릴리스 이름은 `MonglePet macOS 1.4.0 Preview 1`로 한다.
- 기존 `1.3.2` 자산과 태그는 수정하지 않고 새 릴리스에 ZIP·SHA-256·manifest를 게시한다.
- 릴리스 태그는 manifest에 기록된 깨끗한 원격 소스 커밋을 가리킨다.

## 작업 순서

### 공통 계약

- [x] 1단계: schema-v14, 권장 프로필 v10과 Windows 인계가 현재 소스에 반영됐음을 확인한다.

### macOS

- [x] 2단계: 앱 버전과 버전 테스트를 `1.4.0 (8)`로 올린다.
- [x] 3단계: 전체 단위 테스트와 코드 서명 없는 Debug 빌드를 통과한다.
- [x] 4단계: 깨끗한 원격 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성하고 압축 해제본을 검증한다.
- [x] 5단계: GitHub Pre-release를 게시하고 원격 자산과 태그 대상을 다시 검증한다.

### Windows

- [x] 6단계: Windows 소스 변경은 Windows 환경에서 인계 문서에 따라 후속 진행하도록 분리한다.

### 플랫폼 동등성

- [x] 7단계: macOS 배포 결과와 검증 수치를 플랫폼 현황·다운로드 인계 문서에 기록한다.

## 검증 방법

- 전체 `MonglePetTests`와 코드 서명 없는 Debug 빌드를 실행한다.
- Preview 스크립트의 Universal Release 빌드와 ZIP 자체 체크섬 검증을 통과한다.
- 별도 임시 디렉터리에 ZIP을 풀어 버전·빌드·Bundle ID·arm64/x86_64와 기본 자산을 확인한다.
- GitHub 릴리스의 세 자산 이름·크기·digest와 태그 대상 커밋을 로컬 최종본과 비교한다.

## 진행 로그

- 2026-08-27: 원격 `main`과 로컬 기준이 일치하고 GitHub CLI 인증이 유효하며 `macos-v1.4.0-preview.1` 릴리스가 없음을 확인했다.
- 2026-08-27: 기능 확장 범위에 맞춰 앱 버전 `1.4.0 (8)`, 태그 `macos-v1.4.0-preview.1`, 릴리스 이름 `MonglePet macOS 1.4.0 Preview 1`로 확정했다.
- 2026-08-27: 버전 반영 뒤 전체 `MonglePetTests` 503개 중 502개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 코드 서명 없는 Debug 빌드를 확인했다.
- 2026-08-27: 깨끗하게 푸시된 소스 커밋 `78ac0dfb52f0cb4e0d436649603c29dea91e652d`에서 8,833,960 bytes Universal ZIP을 생성했다. SHA-256은 `ebb3a12f0b829671399d44e1fd71ab16486e590f46ac1ec57f0c904aecf55820`이며 별도 경로의 압축 해제본에서 `1.4.0 (8)`, Bundle ID `kr.mapleroom.MonglePet`, arm64·x86_64를 확인했다.
- 2026-08-27: [`macos-v1.4.0-preview.1`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.4.0-preview.1) GitHub Pre-release에 ZIP·SHA-256·manifest를 게시했다. 원격 세 자산을 다시 내려받아 바이트 단위 일치, ZIP digest와 태그 대상을 검증했다.

## 완료 결과

- macOS `1.4.0 (8)` 미서명·미공증 Universal Preview 게시와 원격 자산 검증을 완료했다.
- Windows 구현은 기존 인계 문서에 따라 별도 환경에서 후속 진행한다.

## 남은 위험 / 후속 작업

- 미서명·미공증 Preview이므로 제한된 테스터가 공식 GitHub 파일과 SHA-256을 확인하고 시스템 설정의 개별 앱 승인으로만 실행 여부를 판단해야 한다.
- 실제 다른 Mac에서 설치·첫 실행·재실행·설정 마이그레이션과 최종 몽글이 동작을 확인한다.
- Windows 구현과 실기기 QA가 끝나기 전에는 플랫폼 동등 완료로 표시하지 않는다.
