# Developer ID 공증 DMG 배포

## 상태

- 상태: blocked
- 생성일: 2026-07-26
- 마지막 갱신: 2026-08-13

## 목표

- Mac App Store 밖에서 배포할 MonglePet을 Developer ID로 서명하고 Apple 공증을 거친 DMG로 제공한다.
- 다운로드된 최종 DMG와 내부 앱을 Gatekeeper가 정상 평가하는지 별도 사용자 환경에서 검증한다.

## 선행 조건

- Apple Developer Program 가입
- `Developer ID Application` 인증서와 개인 키 준비
- Phase 10 Preview 기능·문서·수동 QA 완료
- 개인 맥 Release 기준선과 버전·빌드 번호 확정

## 범위

- Release Archive 생성과 Developer ID Application 서명
- App Sandbox 유지, Hardened Runtime 활성화와 entitlement 검토
- 서명된 `MonglePet.app`과 `/Applications` 바로가기를 포함한 읽기 전용 DMG 생성
- 최종 DMG 서명, `notarytool` 제출, 승인 로그 확인과 `stapler` 티켓 부착
- 코드 서명, 공증 티켓, Gatekeeper, DMG 구조와 SHA-256 검증
- 브라우저로 새로 다운로드한 파일의 quarantine 상태를 유지한 실제 설치·실행 스모크 테스트

## 제외 범위

- Mac App Store 배포
- PKG 설치 프로그램
- 자동 업데이트
- Gatekeeper 비활성화 또는 quarantine 속성 제거 안내
- 미서명 Preview ZIP을 DMG로 단순 포장하는 작업

## 결정사항

- DMG는 설치 경험을 제공하는 컨테이너이며 코드 서명이나 공증을 대신하지 않는다.
- 앱 내부의 모든 실행 코드를 먼저 Developer ID로 서명하고, 완성된 최종 DMG도 별도로 서명한다.
- Apple 공증 서비스에는 실제 배포할 최종 DMG를 제출하고 승인 후 같은 파일에 티켓을 스테이플한다.
- `Developer ID Installer`는 PKG용이므로 이 DMG 작업에는 사용하지 않는다.
- `com.apple.security.get-task-allow`은 배포 entitlement에 포함하지 않는다.

## 작업 순서

- [ ] 1단계: Developer ID Application 인증서·팀·키체인과 버전 기준선 확인
- [ ] 2단계: Hardened Runtime·App Sandbox·Release entitlement 검토
- [ ] 3단계: Release Archive를 Developer ID 방식으로 내보내고 앱 서명 검증
- [ ] 4단계: 앱과 `/Applications` 바로가기를 배치한 최종 DMG 생성·서명
- [ ] 5단계: `notarytool submit --wait` 제출과 공증 로그 검토
- [ ] 6단계: `stapler staple`·`stapler validate`, Gatekeeper와 DMG 무결성 검증
- [ ] 7단계: 새 사용자 환경에서 다운로드·마운트·복사·첫 실행·로그인 항목 스모크 테스트
- [ ] 8단계: 최종 DMG의 SHA-256, 버전, 커밋과 사용자 설치 안내 기록

## 검증 방법

```sh
codesign --verify --deep --strict --verbose=2 MonglePet.app
spctl --assess --type execute --verbose=4 MonglePet.app
hdiutil verify MonglePet.dmg
xcrun stapler validate MonglePet.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 MonglePet.dmg
shasum -a 256 MonglePet.dmg
```

- `codesign -d --entitlements :- MonglePet.app`으로 배포 entitlement를 별도 검토한다.
- 공증이 실패하면 `xcrun notarytool log` 결과를 보존하고 서명·타임스탬프·중첩 코드 오류를 수정한 뒤 새 최종 DMG를 만든다.
- Finder에서 DMG를 열고 앱을 `/Applications`로 복사한 뒤 인터넷 다운로드와 동일한 quarantine 경로에서 첫 실행한다.
- 완전 종료·재실행, 설정 열기, 펫 표시와 로그인 항목 켜기·끄기를 확인한다.

## 참고 자료

- [Apple Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Apple Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 진행 로그

- 2026-07-26: 개인 Preview ZIP과 공증된 정식 DMG의 목적을 분리하고 Apple Developer Program 준비 전까지 보류하기로 했다.
- 2026-07-26: 이 맥의 키체인에서 `security find-identity -v -p codesigning` 결과 유효한 코드서명 인증서가 0개임을 확인했다. 실제 Archive·공증은 Developer ID Application 인증서와 팀 준비까지 계속 보류한다.
- 2026-07-26: Release 구성에 Hardened Runtime을 활성화하고, Developer ID Archive·앱 entitlement 검증·DMG 생성과 서명·`notarytool` 제출·스테이플·Gatekeeper·SHA-256 검증을 한 번에 수행하는 `apps/macos/Scripts/build-notarized-dmg.zsh`를 준비했다.
- 2026-07-26: 공개 `apps/macos/DISTRIBUTION.md`에 자격 증명을 저장소에 두지 않는 키체인 프로필 방식, 실행 명령, 독립 설치 검증과 버전·빌드 번호 정책을 기록했다.
- 2026-08-13: 현재 정식 배포 후보 기준을 `1.1.0 (2)`로 갱신했다. 회사 Mac에서는 인증서·공증 작업을 수행하지 않고, Apple Developer Program·Developer ID Application 인증서·개인 키·notarytool 프로필을 준비한 개인 Mac에서만 최종 DMG를 만든다.

## 완료 결과

- 저장소의 DMG 자동화와 Release 보안 설정 준비 완료
- Apple Developer Program, Developer ID Application 인증서·개인 키, Team ID와 notarytool 키체인 프로필 준비 대기

## 남은 위험 / 후속 작업

- 서명된 앱이라도 Hardened Runtime, 타임스탬프 또는 중첩 코드 서명이 잘못되면 공증이 거부될 수 있다.
- 공증 성공만으로 설치 경험이 보장되지는 않으므로 실제 브라우저 다운로드와 별도 사용자 환경의 Gatekeeper 검증이 필요하다.
