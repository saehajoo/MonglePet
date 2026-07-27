# 개인 맥 Preview 배포 파일 생성

## 상태

- 상태: in_progress
- 생성일: 2026-07-24
- 마지막 갱신: 2026-07-26

## 목표

- 기능 범위가 확정된 MonglePet Preview를 개인 맥에서 빌드하고 최종 ZIP과 SHA-256 체크섬을 같은 환경에서 생성한다.
- 생성한 파일이 문서화된 설치·실행 절차로 열리는지 독립적으로 검증한다.

## 범위

- 개인 맥의 깨끗한 저장소 상태와 Xcode 환경 확인
- 버전·빌드 번호와 Git 커밋 식별자 기록
- 재현 가능한 Release 빌드와 미서명·미공증 Preview ZIP 생성
- 최종 ZIP에 대한 SHA-256 체크섬 생성과 재검증
- 압축 해제, 앱 실행, 기본 동작과 macOS 개인정보 보호 및 보안 승인 경로 확인
- GitHub Release에 올릴 파일명, 체크섬과 사용자 안내 확정

## 제외 범위

- 회사 맥에서 최종 배포 파일 생성
- Developer ID Application 서명과 Apple notarization
- Gatekeeper 비활성화 또는 quarantine 속성 제거 안내
- 자동 업데이트와 DMG·PKG 생성

## 열린 질문

- 실제 Preview 버전과 Git 태그는 기능 범위 확정 시 결정한다.

## 결정사항

- 이 계획은 기능 검토와 Preview 범위 확정 후 진행하는 후속 작업 중 최우선순위다.
- SHA-256은 코드 서명이 아니라 최종 ZIP의 무결성 체크섬으로 취급한다.
- 체크섬은 배포할 최종 ZIP이 생성된 뒤 같은 개인 맥에서 만들고, 파일을 다시 계산해 일치 여부를 확인한다.
- DMG로 감싸는 것만으로 미서명 앱의 Gatekeeper 신뢰 문제가 해결되지는 않는다. 현재 Preview는 ZIP을 유지하고, 공증된 DMG는 Developer ID 준비 후 별도 계획에서 만든다.
- Preview 생성 스크립트는 깨끗한 작업 트리에서만 실행하며 dirty 상태를 허용하는 우회 옵션을 두지 않는다.

## 작업 순서

- [x] 1단계: 개인 맥 저장소·Xcode·버전·커밋 기준선 확인
- [ ] 2단계: Release 빌드와 Preview ZIP 생성
- [ ] 3단계: SHA-256 체크섬 생성과 재검증
- [ ] 4단계: 별도 위치에서 압축 해제·실행·핵심 스모크 테스트
- [ ] 5단계: GitHub Release 파일과 사용자 안내 최종 검토

## 검증 방법

- 빌드와 테스트 명령이 기록한 커밋에서 성공하는지 확인한다.
- 체크섬을 두 번 계산해 게시할 값과 최종 ZIP이 일치하는지 확인한다.
- ZIP을 새 디렉터리에 풀고 앱의 버전, 실행, 설정 열기와 기본 펫 표시를 확인한다.
- macOS의 공식 개인정보 보호 및 보안 승인 경로만으로 Preview 앱을 실행할 수 있는지 확인한다.

## 진행 로그

- 2026-07-24: 회사 계정이 연결된 개발 맥과 개인 배포 환경을 분리하기 위해 별도 최우선 후속 작업으로 생성했다.
- 2026-07-26: 개인 맥 저장소가 `main`, `origin/main`과 같은 커밋 `4cc9b0de46cecd0472fdd8711fd7d4a3a77abf25`에서 시작하고 작업 트리가 깨끗함을 확인했다.
- 2026-07-26: Xcode 26.6(17F113), Swift 6.3.3과 활성 개발자 디렉터리 `/Applications/Xcode.app/Contents/Developer`를 확인했다.
- 2026-07-26: macOS 26.3.1의 시스템 Swift 런타임에서 알려진 isolated-deinit/task-local XCTest 종료 오류를 재현했다. 설치 가능한 macOS Tahoe 26.5.2로 업데이트한 뒤 전체 단위 테스트를 재실행해야 하므로 1단계는 아직 완료하지 않는다.
- 2026-07-26: macOS 26.5.2(25F84) 업데이트 후 전체 단위 XCTest 308개가 실행됐고 선택적 로컬 WebP fixture 1개만 건너뛴 채 실패 없이 통과했다. Xcode 26.6 Debug 빌드와 저장소 기준선을 포함해 1단계를 완료했다.
- 2026-07-26: `Scripts/build-preview-zip.zsh`로 Universal Release 앱을 코드서명 없이 빌드하고 `MonglePet-0.1.0-build.1-preview.zip`, SHA-256과 환경 manifest가 생성·재검증되는 것을 임시 경로에서 확인했다. 이 파일은 배포 준비 검증물이며 최종 공개 산출물은 아니다.
- 2026-07-27: 다른 맥에서 원격 변경을 별도 작업 트리로 검토해 전체 단위 XCTest 307개 통과·선택 fixture 1개 건너뜀과 Universal Preview ZIP·SHA-256·manifest 생성을 재현했다. dirty 작업 트리 예외는 산출물 출처를 모호하게 만들 수 있어 제거했다.

## 완료 결과

- Release Preview ZIP 생성 절차 검증 완료, 최종 깨끗한 커밋과 수동 스모크 테스트 대기

## 남은 위험 / 후속 작업

- 미서명·미공증 Preview는 Apple이 개발자와 앱의 변조 여부를 확인하는 정식 배포물이 아니다.
- Apple Developer Program 가입 후 Developer ID 서명과 notarization을 별도 배포 작업으로 진행한다.
- 공증된 DMG 후속 작업은 `2026-07-26-developer-id-dmg-distribution.md`를 따른다.
