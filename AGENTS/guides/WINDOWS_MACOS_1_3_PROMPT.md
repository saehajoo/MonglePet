# Windows 작업 공간 전달 프롬프트: macOS 1.3 동등성

아래 내용을 Windows MonglePet 작업 공간에 전달한다.

---

MonglePet Windows 앱에 macOS `1.3.1 (6)`에서 확정한 새 내장 몽글이, 펫 최소 앱 버전 권장 정책과 PNG·스프라이트 제작기 개선을 모두 반영해주세요.

`macos-v1.3.1-preview.1`의 기준 소스 커밋 `89ceb5444478eeb2717ac29ec930f4661503a794`와 최신 `main`의 인계 문서를 함께 확인하세요. 단일 PNG와 스프라이트 선택 결과는 투명 격자·바깥 캔버스 테두리·실제 crop 전체 범위의 파란 경계를 동일하게 표시하세요. PNG는 왼쪽 원본 자르기 캔버스와 오른쪽 상단 고정 결과 패널을 동시에 보여주고, 선택 범위와 crop 썸네일 PNG 목록만 결과 아래에서 독립 스크롤하세요. 다중 선택 결과는 고정 패널의 이전·다음 버튼으로 탐색하며 별도 하단 결과 목록은 두지 않습니다. 스프라이트 전체 시트는 원본 종횡비와 가용 높이에 맞춰 불필요한 위·아래 공백을 줄이고, 선택 영역 미리보기는 오른쪽 상단에 고정한 채 나머지 설정만 독립 스크롤하세요. 1×에서는 내부 이미지 pan이 바깥 스크롤을 가로채지 않고 확대했을 때만 양축 pan을 사용하며, 확대·축소 버튼 크기와 높이를 완전히 같게 맞추세요.

먼저 `AGENTS.md`, `apps/windows/AGENTS.md`, `AGENTS/guides/WINDOWS_MACOS_1_3_HANDOFF.md`, `AGENTS/guides/WINDOWS_BUILTIN_MONGLE_HANDOFF.md`, `AGENTS/specifications/PET_PACKAGE.md`, `AGENTS/project/DECISIONS.md`의 D-086~D-090, `AGENTS/project/PLATFORM_PARITY.md`를 읽으세요. `git status -sb`와 원격 차이를 확인하고 최신 이미지 편집 보정 및 릴리스 인계 커밋이 없으면 먼저 `git pull --ff-only` 필요 여부를 알려주세요. 사용자 변경을 보존하고 Windows 소스 수정 전 별도 작업 계획을 만드세요.

핵심 요구사항:

- 펫 콘텐츠 `version`은 한글·영문 자유 문자열이며 자동 분석·승격하지 않습니다.
- 앱 호환 버전만 숫자형 SemVer로 검증합니다.
- 로컬·웹의 높은 최소 앱 버전은 설치 차단이 아니라 업데이트 권장입니다. 일부 기능 차이 안내와 `https://mapleroom.kr/monglepet/download` 버튼을 제공하세요.
- 업데이트 확인·자동 업데이트는 구현하지 마세요. 보안·형식 오류 차단은 유지하세요.
- crop → 좌우·상하 flip → 공통 캔버스 배치 순서로 최종 atlas에 굽고 schema는 바꾸지 않습니다.
- PNG 편집 중 추가, 다중 선택·결과 미리보기·일괄 flip, 1×~8× 확대와 안정적인 crop을 구현하세요.
- 스프라이트 선택/범위 편집, 읽기/클릭 순서, 선택 결과 이전·다음 미리보기, frame별 flip, 1×~8× 확대를 구현하세요.
- 프레임 복사는 source·현재 간격·배치를 보존한 독립 항목을 바로 다음에 넣습니다.
- 모든 새 프레임 기본값은 450ms이고 기존 간격은 보존합니다.
- 현재 단순 `PetAnimationEditorControl.xaml` UI를 handoff의 macOS 정보 구조와 사용자 결과에 맞추되 WinUI 3·Mica·네이티브 컨트롤을 유지하세요.
- `shared/BuiltInPets/Mongle.monglepet`을 Windows output/publish에 포함하고 내장 몽글이 loader·기본 프로필·이관을 구현하세요. macOS 자산 폴더를 참조하거나 공통 built-in을 다시 만들지 마세요.
- 공통 권장 프로필에는 앱 규칙이 없으므로 실제 Windows Codex의 `pfn:`/`exe:` 식별자를 확인해 built-in 전용 기본값에 추가하세요.

자동 테스트, 실제 packaged/unpackaged QA, 최소 창 높이의 전체 본문 스크롤, 1×/확대 viewport 스크롤 소유권, 100%·150%·200% DPI의 동일한 `+`·`−` 버튼, Narrator·큰 이미지 drag 성능과 Windows→macOS 교차 왕복을 `WINDOWS_MACOS_1_3_HANDOFF.md`의 완료 조건대로 수행하세요. 공개 Windows `1.2.0.13`을 덮어쓰지 말고 새 버전을 올리세요. 사용자가 남은 수정과 검토 완료를 확정하기 전에는 GitHub Release를 게시하지 말고, 확정 후 모든 구현·검증을 커밋·푸시한 다음 새 Windows Pre-release와 원격 설치기 digest를 검증하세요.

마지막 보고에는 버전과 태그, 변경 파일, 테스트 개수, Debug·Release 빌드, packaged/unpackaged 실제 QA, 교차 왕복, 설치기 digest, 커밋·푸시·릴리스 상태와 남은 위험을 구분해 적으세요. Windows 실제 QA 전에는 플랫폼 동등 완료로 표시하지 마세요.

---
