# Windows 작업 공간 전달 프롬프트: 내장 몽글이 교체

아래 내용을 Windows의 MonglePet 작업 공간에 그대로 전달한다.

---

MonglePet Windows 앱의 내장 기본 펫을 macOS 최신 작업 트리에 확정한 몽글이
`1.0.3`으로
교체해주세요.

작업을 시작하기 전에 다음 문서를 순서대로 모두 읽고 지침을 따르세요.

1. `AGENTS.md`
2. `apps/windows/AGENTS.md`
3. `AGENTS/guides/WINDOWS_BUILTIN_MONGLE_HANDOFF.md`
4. `AGENTS/specifications/PET_PACKAGE.md`
5. `AGENTS/project/DECISIONS.md`의 D-022·D-086·D-100~D-102
6. `AGENTS/project/PLATFORM_PARITY.md`
7. `apps/windows/README.md`

먼저 `git status -sb`, 현재 branch와 원격 차이를 확인하고 macOS 내장 몽글이
구현 커밋이 없으면 임의 구현하지 말고 `git pull --ff-only`가 필요한지 알려주세요.
사용자 변경이 있으면 보존하세요. Windows 소스 변경 전에
`AGENTS/guides/DEVELOPMENT_WORKFLOW.md`에 따라 별도 작업 계획을 만들고
`AGENTS/work_plans/INDEX.md`에 등록하세요.

핵심 요구사항은 다음과 같습니다.

- 이름 `몽글이`, 펫 버전 `1.0.3`, 제작자 `운영자`
- 설명 `MonglePet에서 기본으로 제공되는 몽글펫입니다.`
- 13개 모션·53프레임과 모든 이미지 효과를 원본 그대로 적용
- 기본 행동은 현재 펫의 `기본` 애니메이션, 60초 입력 없음은 `자는 중`
- 우선순위 `입력 없음 규칙 → 앱 사용 규칙 → 표시 및 이동`, 기본 앱 규칙 없음
- 마우스 도망가기, 포인터 거리 256·감지 거리 160·2~6초 랜덤 머무르기와 세 이동 방식의 4방향 행동 적용
- 방향 행동은 왼쪽/오른쪽에 각각 `왼쪽 보글보글`/`오른쪽 보글보글`, 위/아래에 `위`/`아래` 적용
- 쓰다듬기 행동 `행복`은 모션 `행복`, 말풍선은 기본 비활성화
- 권장 프로필 v10의 세 이동 방식과 도망가기 평상시 자유 이동 값을 서로 독립 적용
- 펫 표시 50%, 클릭 통과·겹침 투명화 켬·겹침 불투명도 45%·픽셀 표시 끔·불투명도 100%까지 적용하되 화면 좌표·monitor·모든 펫 공통 이동 범위·깨움 상태는 보존
- 기존 built-in key와 활성 instance/profile ID 유지
- 신규·정확히 종전 1.0.1 또는 1.0.2 미수정 built-in 프로필만 새 기본값 적용
- 수정된 built-in 프로필의 구조와 설치 펫 중립 기본값은 보존하고 제거된 모션 이름 참조만 새 이름으로 연결

현재 `shared/Samples/ReadOnlySample.monglepet`은 테스트 fixture와 built-in runtime을
동시에 담당하고 있습니다. 이 fixture는 변경하지 말고, 이미 확정된
`shared/BuiltInPets/Mongle.monglepet` 공통 데이터 기준본을 Windows output/publish에
포함하세요. 기준본을 다시 만들거나 덮어쓰지 말고 Windows runtime이 `apps/macos` 파일을
직접 참조하면 안 됩니다.

`App.xaml.cs`의 `LoadBundledSample`, `BundledSamplePath`, built-in package resolver와
legacy cycle resolver를 새 built-in package 경계로 교체하세요.
`BehaviorProfileDefaults`, `DefaultAppSettingsDocument`, schema-v11 누락 프로필
복구와 기존 설정 이관을 built-in 전용값/설치 펫 중립값으로 분리하세요.

새 schema-v10 권장 프로필에는 기본 앱 규칙이 없습니다. Windows Codex의 `pfn:` 또는 `exe:`
식별자를 추측하거나 새 기본 규칙으로 추가하지 마세요. 사용자가 기존에 만든 앱
규칙은 프로필 이관에서 보존하고 일반 앱 규칙 실행 회귀만 검증하세요.

공개된 Windows `1.3.0.13` 산출물을 덮어쓰지 마세요. 최신 통합 작업 범위와 배포
조건은 `WINDOWS_MACOS_1_3_PROMPT.md`를 따르세요.

필수 검증:

- 13개 PNG SHA-256·크기, 13개 모션·53프레임·시간·atlas 범위
- fresh/종전 미수정/수정됨/설치 펫/다중 인스턴스 설정 시나리오
- 내장 펫 내보내기 금지와 `ReadOnlySample` 패키지 회귀
- Debug·Release 전체 xUnit과 솔루션 빌드
- packaged loose AppX와 unpackaged publish의 built-in content 포함
- 실제 Windows에서 `기본` 애니메이션, 60초 수면, 도망가기·자유 이동 4방향,
  랜덤 머무르기, 쓰다듬기, 재실행과 기존 설정·앱 규칙 보존
- 50% 기본 크기·혼합 DPI, packaged·unpackaged 실제 앱 QA

완료 후 `AGENTS/project/TESTING.md`, 작업 계획과
`AGENTS/project/PLATFORM_PARITY.md`를 갱신하세요. Windows 실제 QA까지 끝나기 전에는
플랫폼 동등 완료로 표시하지 마세요. 마지막 보고에는 변경 파일, 테스트 수,
빌드 결과, 실제 QA 결과, 남은 위험과 커밋·푸시·릴리스 상태를 구분해 적어주세요.

---
