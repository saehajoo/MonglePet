# MonglePet for macOS

현재 개발 중인 MonglePet 네이티브 macOS 앱이다.

- Xcode 프로젝트: `MonglePet.xcodeproj`
- 앱 소스: `MonglePet/`
- 단위 테스트: `MonglePetTests/`
- UI 테스트: `MonglePetUITests/`
- 배포 자동화: `Scripts/`

다중 펫 Release CPU·메모리 기준선은 사용자 설정과 분리된 임시 저장소로 측정한다.

```sh
apps/macos/Scripts/measure-multi-pet-release.zsh
```

기본값은 위치 고정 1·2·4·8마리를 각 30초 측정한다. `MONGLEPET_QA_COUNTS`,
`MONGLEPET_QA_DURATION_SECONDS`, `MONGLEPET_QA_WARMUP_SECONDS`,
`MONGLEPET_QA_MOVEMENT_MODE`(`fixed`, `cursor-following`, `free-roaming`,
`cursor-avoiding`)로 workload를 바꿀 수 있다. 결과 TSV는 기본적으로 `dist/qa/`에
생성되며 앱은 `--ui-testing` 임시 설정만 사용한다.
TSV에는 평균·최대 RSS와 함께 시작·종료 RSS 및 순증가량이 기록된다.
정확한 비교를 위해 평소 실행 중인 MonglePet은 종료하고 같은 화면 구성에서 측정한다.
마우스 따라가기는 측정 중 실제 포인터를 이동해야 이동 중 비용을 반영한다.

공통 제품·패키지 명세와 작업 계획은 저장소 루트의 `AGENTS.md`와 `AGENTS/`에서 관리한다. 빌드와 테스트 명령은 `AGENTS.md`, 배포 절차는 `DISTRIBUTION.md`를 확인한다.
