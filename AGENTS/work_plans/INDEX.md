# MonglePet 작업 계획 인덱스

큰 기능, 다중 파일 변경, 리팩터링과 장기 작업의 계획 및 진행 상태를 관리한다. 새 작업을 만들기 전에 같은 목표의 기존 계획이 있는지 먼저 확인한다.

작업 절차와 템플릿은 `../guides/DEVELOPMENT_WORKFLOW.md`를 따른다.

## 진행 중

| 상태 | 작업명 | 파일 | 마지막 갱신 |
| --- | --- | --- | --- |
| in_progress | macOS 1.3.1 이미지 편집 UI 보정 Preview 릴리스 | `tasks/2026-08-24-macos-1-3-1-image-editor-polish-release.md` | 2026-08-24 |
| in_progress | 웹 펫 URL 가져오기 | `tasks/2026-08-23-web-pet-url-import.md` | 2026-08-24 |
| in_progress | 스프라이트 시트 순서·격자·프레임 간격 개선 | `tasks/2026-08-23-sprite-sheet-ordering-and-duration.md` | 2026-08-23 |
| in_progress | Windows 웹 배포와 자동 업데이트 준비 | `tasks/2026-08-09-windows-web-distribution.md` | 2026-08-16 |
| in_progress | Windows 말풍선 타이밍과 설정 UI 다듬기 | `tasks/2026-08-09-windows-speech-timing-and-ui-polish.md` | 2026-08-09 |
| completed | Windows macOS 기능 동등성 완성 | `tasks/2026-08-09-windows-macos-feature-parity-completion.md` | 2026-08-09 |
| completed | Windows 로그인 시 자동 실행 | `tasks/2026-08-09-windows-login-launch.md` | 2026-08-09 |
| completed | Windows 로컬 가져오기 검토와 내보내기 | `tasks/2026-08-09-windows-local-sharing.md` | 2026-08-09 |
| complete | Windows 개발 기준선·공통 계약·오버레이 실험 | `tasks/2026-08-08-windows-foundation-and-overlay.md` | 2026-08-08 |
| in_progress | Phase 10 공개 준비와 이동 성능 보완 | `tasks/2026-07-24-phase-10-release-preparation.md` | 2026-07-31 |
| in_progress | 멀티펫 런타임과 활성 펫 관리 | `tasks/2026-08-13-multi-pet-runtime.md` | 2026-08-13 |

## 보류 / 대기

| 상태 | 작업명 | 파일 | 마지막 갱신 | 사유 |
| --- | --- | --- | --- | --- |
| blocked | Developer ID 공증 DMG 배포 | `tasks/2026-07-26-developer-id-dmg-distribution.md` | 2026-07-26 | Apple Developer Program 가입과 Developer ID Application 인증서 준비 후 진행 |

## 완료

| 상태 | 작업명 | 파일 | 완료일 |
| --- | --- | --- | --- |
| completed | 이미지 편집 결과 미리보기와 스크롤 다듬기 | `tasks/2026-08-24-image-editor-preview-polish.md` | 2026-08-24 |
| completed | macOS 1.3 편집기·호환성 안내 Preview 릴리스 | `tasks/2026-08-24-macos-1-3-editor-and-compatibility-release.md` | 2026-08-24 |
| completed | 내장 몽글이 교체와 기본 행동 프로필 적용 | `tasks/2026-08-24-builtin-mongle-replacement.md` | 2026-08-24 |
| completed | Windows 1.2.0 Preview 배포 | `tasks/2026-08-24-windows-1-2-preview-release.md` | 2026-08-24 |
| completed | macOS 1.2.0 Preview 배포 | `tasks/2026-08-23-macos-1-2-preview-release.md` | 2026-08-24 |
| completed | 개인 맥 Preview 배포 파일 생성 | `tasks/2026-07-24-personal-mac-preview-artifact.md` | 2026-08-14 |
| completed | Windows unpackaged EXE 설치기 | `tasks/2026-08-09-windows-exe-installer.md` | 2026-08-09 |
| completed | Windows 설정 화면 시각적 동등성 | `tasks/2026-08-09-windows-settings-visual-parity.md` | 2026-08-09 |
| completed | Windows 아이콘과 설정 디자인 정렬 | `tasks/2026-08-09-windows-icon-and-settings-design.md` | 2026-08-09 |
| completed | Windows 말풍선 런타임과 설정 UI | `tasks/2026-08-09-windows-speech-bubbles.md` | 2026-08-09 |
| completed | Windows 전면 앱 대표 창 선호 이동 | `tasks/2026-08-09-windows-frontmost-window-preference.md` | 2026-08-09 |
| completed | Windows 알파 호버와 겹침 투명화 | `tasks/2026-08-09-windows-alpha-hover-and-overlap-fade.md` | 2026-08-09 |
| completed | Windows 이동·드래그·쓰다듬기 런타임 | `tasks/2026-08-09-windows-movement-and-petting-runtime.md` | 2026-08-09 |
| completed | Windows notification area 빠른 제어 | `tasks/2026-08-09-windows-notification-area-quick-controls.md` | 2026-08-09 |
| completed | Windows 자동 규칙 앱 선택기 | `tasks/2026-08-09-windows-application-rule-picker.md` | 2026-08-09 |
| completed | Windows 행동 루틴과 자동 규칙 편집기 | `tasks/2026-08-09-windows-behavior-editors.md` | 2026-08-09 |
| completed | Windows 활동 감지와 자동 규칙 연결 | `tasks/2026-08-09-windows-activity-monitoring.md` | 2026-08-09 |
| completed | Windows 행동 런타임과 기본 설정 UI | `tasks/2026-08-09-windows-behavior-runtime-basic-ui.md` | 2026-08-09 |
| completed | Windows 화면 표시 설정 런타임 적용 | `tasks/2026-08-08-windows-display-settings-runtime.md` | 2026-08-08 |
| completed | Windows schema-v10 Domain 매핑과 항목 복구 | `tasks/2026-08-08-windows-settings-domain-mapping.md` | 2026-08-08 |
| completed | Windows 설정 schema-v1~v9 마이그레이션 | `tasks/2026-08-08-windows-settings-migration.md` | 2026-08-08 |
| completed | Windows 설정 저장과 펫 라이브러리 관리 UI | `tasks/2026-08-08-windows-settings-and-library-ui.md` | 2026-08-08 |
| completed | Windows 로컬 펫 라이브러리와 실행 중 전환 | `tasks/2026-08-08-windows-pet-library.md` | 2026-08-08 |
| completed | 펫 라이선스 메타데이터 제거 | `tasks/2026-08-07-remove-pet-license-metadata.md` | 2026-08-07 |
| completed | 행동 대사 우선순위와 주기 대사 목록 분리 | `tasks/2026-07-31-speech-priority-and-periodic-list.md` | 2026-07-31 |
| completed | 말풍선 테마 커스텀 | `tasks/2026-07-30-speech-bubble-themes.md` | 2026-07-31 |
| completed | 펫별 말풍선 1차 기능 | `tasks/2026-07-30-speech-bubbles.md` | 2026-07-31 |
| completed | 자동 규칙 앱 선택기 | `tasks/2026-07-24-application-rule-picker.md` | 2026-07-31 |
| completed | 웹 커뮤니티 인계 지침 | `tasks/2026-07-31-web-community-handoff.md` | 2026-07-31 |
| completed | macOS·Windows 플랫폼 디렉터리 분리 | `tasks/2026-07-31-platform-directory-split.md` | 2026-07-31 |
| completed | 스프라이트 시트 애니메이션 가져오기 | `tasks/2026-07-27-sprite-sheet-animation-import.md` | 2026-07-31 |
| completed | 입력 없음 규칙 즉시 해제 | `tasks/2026-07-31-immediate-idle-rule-exit.md` | 2026-07-31 |
| completed | 상태 메뉴 빠른 제어 | `tasks/2026-07-31-status-menu-quick-controls.md` | 2026-07-31 |
| completed | 말풍선 배치·다중 화면 도망·즉시 행동 전환 | `tasks/2026-07-31-speech-placement-escape-and-immediate-behavior.md` | 2026-07-31 |
| completed | 마우스 도망가기 이동 모드 | `tasks/2026-07-30-cursor-avoiding-movement.md` | 2026-07-30 |
| completed | Phase 9C 방향별 이동 애니메이션 | `tasks/2026-07-29-directional-movement-animations.md` | 2026-07-30 |
| completed | 호버 쓰다듬기 상호작용 | `tasks/2026-07-29-hover-petting-interaction.md` | 2026-07-29 |
| completed | Phase 9B 다중 모니터·표시·호환성 보완 | `tasks/2026-07-23-phase-9b-display-and-compatibility.md` | 2026-07-23 |
| completed | Phase 9A 공유 권장 프로필 | `tasks/2026-07-23-phase-9a-shared-pet-profile.md` | 2026-07-23 |
| completed | Phase 9 펫 이동 모드와 상호작용 | `tasks/2026-07-22-phase-9-cursor-following.md` | 2026-07-23 |
| completed | Phase 8 로컬 펫 공유 | `tasks/2026-07-22-phase-8-local-pet-sharing.md` | 2026-07-23 |
| completed | Phase 7 애니메이션·행동 모델 v2와 펫별 설정 | `tasks/2026-07-22-phase-7-animation-behavior-v2.md` | 2026-07-23 |
| completed | Phase 6 펫 스튜디오와 메타데이터 편집 | `tasks/2026-07-22-phase-6-pet-studio.md` | 2026-07-22 |
| completed | 사용자 자유 행동 기본값 전환 | `tasks/2026-07-22-custom-behavior-defaults.md` | 2026-07-22 |
| completed | Phase 5E 펫 라이브러리와 실행 중 펫 교체 | `tasks/2026-07-22-phase-5e-pet-library-runtime.md` | 2026-07-22 |
| completed | Phase 5D 행동 루틴과 자동 규칙 편집기 | `tasks/2026-07-22-phase-5d-behavior-editors.md` | 2026-07-22 |
| completed | Phase 5C 행동 런타임과 기본 프리셋 | `tasks/2026-07-22-phase-5c-behavior-runtime-presets.md` | 2026-07-22 |
| completed | Phase 5B 설정 적용과 기본 설정 UI | `tasks/2026-07-22-phase-5b-settings-application-ui.md` | 2026-07-22 |
| completed | Phase 5A 설정 저장과 복원 기반 | `tasks/2026-07-22-phase-5a-settings-storage.md` | 2026-07-22 |
| completed | Phase 4 macOS 활동 감지 | `tasks/2026-07-22-phase-4-macos-activity-monitoring.md` | 2026-07-22 |
| completed | Phase 3 행동 엔진 | `tasks/2026-07-22-phase-3-behavior-engine.md` | 2026-07-22 |
| completed | Phase 2D 호환 가져오기 | `tasks/2026-07-21-phase-2d-compatible-importers.md` | 2026-07-21 |
| completed | Phase 2C 외부 패키지 설치 | `tasks/2026-07-21-phase-2c-package-installation.md` | 2026-07-21 |
| completed | Phase 2B MonglePet 패키지 로더 | `tasks/2026-07-21-phase-2b-package-loader.md` | 2026-07-21 |
| completed | Phase 2A 모션 모델과 내장 펫 재생 | `tasks/2026-07-21-phase-2a-motion-runtime.md` | 2026-07-21 |
| completed | Phase 1 앱 셸과 펫 오버레이 | `tasks/2026-07-21-phase-1-overlay-shell.md` | 2026-07-21 |
