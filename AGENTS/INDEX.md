# MonglePet 문서 인덱스

이 디렉터리는 프로젝트 작업에 필요한 제품 문서, 기술 규칙, 명세, 작업 계획을 한곳에서 관리한다. 최상위 `AGENTS.md`는 작업 진입점이며 이 문서는 전체 문서의 위치와 상태를 관리한다.

## 프로젝트 문서

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| `project/PRODUCT.md` | 제품 목표, 원칙, MVP 범위와 완료 기준 | active |
| `project/ARCHITECTURE.md` | 저장소·플랫폼별 구조, 계층 책임과 의존성 규칙 | draft |
| `project/ROADMAP.md` | 단계별 개발 순서와 현재 진행 단계 | active |
| `project/PLATFORM_PARITY.md` | macOS 우선 개발 절차와 Windows 기능 동등성 현황 | active |
| `project/TESTING.md` | 빌드, 테스트, 성능 및 수동 QA 기준 | active |
| `project/DECISIONS.md` | 확정된 제품·기술 결정 기록 | active |

## 기능 명세

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| `specifications/BEHAVIOR_MODEL.md` | 자동·수동 행동 결정과 전환 규칙 | active |
| `specifications/PET_PACKAGE.md` | `.monglepet` 패키지와 가져오기 규격 | draft |
| `specifications/SETTINGS_SCHEMA.md` | JSON 설정 저장, 복원과 마이그레이션 규칙 | draft |

## 작업 가이드와 계획

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| `guides/DEVELOPMENT_WORKFLOW.md` | 큰 작업의 계획·구현·검증 절차 | active |
| `guides/WEB_COMMUNITY_HANDOFF.md` | 별도 웹 커뮤니티 저장소의 초기 설계·보안·인계 지침 | draft |
| `guides/WEB_COMMUNITY_SERVER_PROMPT.md` | 별도 웹 서버 담당자에게 전달할 복사 가능한 구현 프롬프트 | active |
| `guides/WINDOWS_WEB_PET_IMPORT_HANDOFF.md` | macOS 웹 펫 가져오기와 보관함 UI의 Windows 구현·QA 인계 | active |
| `guides/WINDOWS_BUILTIN_MONGLE_HANDOFF.md` | 새 내장 몽글이 자산·기본 프로필의 Windows 구현·QA 인계 | active |
| `guides/WINDOWS_BUILTIN_MONGLE_PROMPT.md` | Windows 작업 공간에 전달할 내장 몽글이 구현 프롬프트 | active |
| `guides/WINDOWS_MACOS_1_3_HANDOFF.md` | macOS 1.3 펫 호환성·이미지 편집기·내장 펫 Windows 구현 인계 | active |
| `guides/WINDOWS_MACOS_1_3_PROMPT.md` | Windows 작업 공간에 전달할 macOS 1.3 동등성 프롬프트 | active |
| `guides/WINDOWS_BEHAVIOR_CENTRIC_HANDOFF.md` | 행동 중심 schema-v14·권장 프로필 v10·독립 이동·전체 옵션 공유·WinUI·런타임 Windows 구현 인계 | active |
| `guides/MACOS_PET_EDITOR_FOLLOWUP.md` | Windows에서 먼저 확정한 제작 버전·새 활성 인스턴스 결과의 macOS 후속 인계 | pending |
| `guides/PREVIEW_DOWNLOAD_HANDOFF.md` | Windows·macOS Preview 웹 다운로드 화면 전달 자료 | active |
| `guides/PREVIEW_DOWNLOAD_SERVER_PROMPT.md` | 별도 서버 담당자에게 전달할 Preview 다운로드 화면 구현 프롬프트 | active |
| `work_plans/INDEX.md` | 개별 작업 계획과 진행 상태 목록 | active |
| `work_plans/tasks/*.md` | 작업별 목표, 체크리스트, 결정 및 결과 | 필요할 때 생성 |

## 플랫폼 지침과 공유 자료

| 문서 | 역할 | 상태 |
| --- | --- | --- |
| `../apps/macos/AGENTS.md` | macOS Swift·Xcode·배포 작업 지침 | active |
| `../apps/windows/AGENTS.md` | 후속 Windows 네이티브 구현 경계와 시작 조건 | planned |
| `../shared/README.md` | 플랫폼 공통 샘플·fixture 관리 범위 | active |

## 관리 규칙

- 새 문서를 추가하거나 파일을 이동할 때 이 인덱스를 함께 갱신한다.
- 같은 사실을 여러 문서에 복사하지 않고 책임이 있는 한 문서만 원본으로 삼는다.
- 제품 범위는 `PRODUCT.md`, 장기 순서는 `ROADMAP.md`, 실제 진행 기록은 `work_plans/`에서 관리한다.
- 구현 기준이 되는 세부 동작은 `specifications/`에 기록한다.
- 완료한 작업 계획은 삭제하지 않고 `work_plans/INDEX.md`의 완료 영역으로 옮긴다.
