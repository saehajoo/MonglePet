# Windows 내장 몽글이 교체 인계

## 목적과 현재 상태

macOS `1.3.0 (5)` Preview에 포함한 새 내장 기본 펫 몽글이의 자산, 메타데이터와
권장 프로필을 Windows 네이티브 앱에 동등하게 반영하기 위한 인계 문서다.
Windows 소스 변경, 빌드와 실제 QA는 Windows 작업 공간에서 수행한다.

- macOS: 구현 및 자동 검증 완료, 실제 앱 QA 대상
- Windows: 미적용
- 공통 `.monglepet` schema 변경: 없음
- 기준 웹 펫: `monglepet-b85fa6307ce5`, 버전 `1.0.1`
- 기준 패키지: 971,514 bytes
- 기준 패키지 SHA-256: `00503aab356602e0af8339201c653af05cd24aea8db7dca561e6508d519e8617`

## Windows 작업 전 필수 확인

Windows 작업 공간에서는 다음 순서로 문서를 읽고 별도 작업 계획을 만든다.

1. `AGENTS.md`
2. `apps/windows/AGENTS.md`
3. 이 문서
4. `AGENTS/specifications/PET_PACKAGE.md`
5. `AGENTS/project/DECISIONS.md`의 D-022·D-086~D-088
6. `AGENTS/project/PLATFORM_PARITY.md`
7. `apps/windows/README.md`

작업 시작 전 macOS 구현 커밋이 원격에 올라갔고 Windows 작업 공간이 이를
`pull --ff-only`로 받은 상태인지 확인한다. Windows 소스를 수정하기 전에
`AGENTS/guides/DEVELOPMENT_WORKFLOW.md`에 따라 별도 Windows 작업 계획을 만들고
`공통 계약 → Windows 구현 → packaged/unpackaged 검증 → 플랫폼 동등성` 단계를
분리한다. macOS Swift·AppKit 소스는 수정하거나 C#으로 번역하지 않는다.

## 확정 메타데이터

| 항목 | 값 |
| --- | --- |
| 내부 예약 ID | 플랫폼의 기존 built-in key 유지 |
| 표시 이름 | `몽글이` |
| 펫 버전 | `1.0.1` |
| 제작자 | `운영자` |
| 설명 | `MonglePet에서 기본으로 제공되는 몽글펫입니다.` |
| 기본 모션 | `기본` |

웹 패키지의 사용자 펫 ID를 내장 예약 ID로 저장하지 않는다. 기존 built-in key를
유지해야 저장된 활성 인스턴스와 프로필 참조가 끊기지 않는다.

## 자산과 모션 계약

Windows 작업은 아래 버전 관리 PNG를 원본으로 사용한다. 파란·청록 입자와
외곽선은 의도한 표현이므로 제거하거나 다시 보정하지 않는다. 모든 프레임은
`150×150px`, y=0이고 각 atlas를 왼쪽에서 오른쪽으로 150px씩 읽는다.

| 모션 | macOS 원본 PNG | atlas 크기 | 프레임/간격 | SHA-256 |
| --- | --- | ---: | --- | --- |
| 기본 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleDefault.imageset/builtin-mongle-default.png` | 1050×150 | 7×450ms | `290e1f91ee9ce435c07a711b7104af3aaf97ba6b7088f757b9ab632f6c24c0d5` |
| 위로 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleUp.imageset/builtin-mongle-up.png` | 600×150 | 4×450ms | `84060bb36a96b7d10a2b69624327bb979241a6e1db9ce4856c591f54f4984764` |
| 일하는 중 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleWorking.imageset/builtin-mongle-working.png` | 1050×150 | 7×450ms | `847cba47b47617e7ad3f9676b1de4fbaf378171c996639754a33b5c7c7318e1a` |
| 정면 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleFront.imageset/builtin-mongle-front.png` | 900×150 | 6×450ms | `6615c6dde6b043d4e7c432532108a87426520e3757d47416a760c305cddb5536` |
| 자는중 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleSleeping.imageset/builtin-mongle-sleeping.png` | 300×150 | 450ms, 3000ms | `d49b32daceac70dfc0f6c5882e3cdf6aa4718c47d102883880ce444f6f05723f` |
| 물뿜기 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleSpouting.imageset/builtin-mongle-spouting.png` | 300×150 | 2×450ms | `df99284ac3f9c542b2ea356fbd71af882c140a4345fe0ef91abd3ef69816cefa` |
| 찾는 중 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleSearching.imageset/builtin-mongle-searching.png` | 300×150 | 2×450ms | `f6c209737bafee36b63c74f9d9135345ceb9ba94de1c923a6647a464e2ab1e91` |
| 해피 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleHappy.imageset/builtin-mongle-happy.png` | 300×150 | 2×450ms | `3f83e7741388df710f113cfcb9a8a4c44852785a68c1f321e8077c5766c6bf7d` |
| 오른쪽 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleRight.imageset/builtin-mongle-right.png` | 150×150 | 1×450ms | `f4659fe98a8b727e07bab3f0b4a31657b7cddd42deef424746bb459d69c5db42` |
| 보글보글 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleBubbles.imageset/builtin-mongle-bubbles.png` | 450×150 | 3×450ms | `ae379cb7785c8e01b46f07e1df59244327a29f0de72b262b305ec35be509d2e3` |

총 10개 모션, 36프레임이며 모두 반복 재생한다.

## 기본 프로필 계약

새 built-in 프로필과 종전의 수정되지 않은 built-in 기본 프로필에만 다음 값을
적용한다. 사용자가 수정한 기존 built-in 프로필과 설치 펫의 일반 기본값은
덮어쓰지 않는다.

- 모드: 자동
- 기본 루틴: `현재 펫의 기본 애니메이션 → 물뿜기 → 정면`, 각 1회, 루틴 반복
- `수면 중`: `자는중` 1회, 반복
- `일해라`: `일하는 중` 1회, 반복
- 입력 없음 60초: `수면 중`, priority 1
- 앱 규칙: Codex가 전면일 때 `일해라`, priority 0
- 이동: 마우스 도망가기
- 일반 속도 160, 포인터 거리 96, 정지 반경 16, 자유 이동 대기 6000ms
- 전면 창 선호 활성화
- 도망 감지 거리 160, 도망 속도 320, 정지 시 제자리
- 이동 fallback `보글보글`
- 방향 모션: 왼쪽 `보글보글`, 오른쪽 `오른쪽`, 위 `위로`, 아래 `정면`
- 대각선 방향 모션 비활성화
- 쓰다듬기: `해피`
- 말풍선: 기본값이며 비활성화

macOS 패키지의 앱 규칙 식별자 `com.openai.codex`는 Bundle Identifier라서
Windows에서 그대로 사용하면 동작하지 않는다. Windows 앱 선택기가 반환하는
실제 Codex PFN 또는 `exe:` 식별자를 사용하고 packaged/unpackaged 환경에서
전면 앱 전환을 검증한다. 임의의 PFN이나 실행 파일명을 하드코딩하지 않는다.

## Windows 구현 위치

현재 Windows built-in은 다음 세 지점에서 테스트용 패키지와 결합되어 있다.

- `App.xaml.cs`: `LoadBundledSample()`, `BundledSamplePath`,
  `ResolvePackage(PetBehaviorKey.BuiltIn)`, `ResolveLegacyMotionCycleMilliseconds()`
- `MonglePet.Windows.csproj`: `shared/Samples/ReadOnlySample.monglepet`을 앱 출력과
  publish에 `Samples/ReadOnlySample.monglepet`으로 복사
- `DefaultAppSettingsDocument.cs`와 `BehaviorProfileDefaults.cs`: 모든 펫에 공통인
  중립 기본 프로필 생성

다음 경계로 변경한다.

1. `shared/Samples/ReadOnlySample.monglepet`은 패키지 로더·가져오기 테스트
   fixture로 그대로 유지한다. 파일 내용이나 테스트 의미를 새 몽글이로 바꾸지 않는다.
2. 저장소에 확정된 `shared/BuiltInPets/Mongle.monglepet/` 플랫폼 공통 데이터
   기준본을 그대로 사용한다. 새 디렉터리를 다시 만들거나 외부 패키지로 덮어쓰지
   않는다. `recommended-profile.json`은 플랫폼 전용 앱 규칙을 의도적으로 제외한다.
3. 위 표의 macOS PNG 경로는 원본 대조용일 뿐 Windows runtime이
   `apps/macos`를 직접 참조하지 않게 한다. 공통 built-in 디렉터리의 SHA-256과
   크기를 검증하고 그것만 Windows 앱 content로 포함한다.
4. `MonglePet.Windows.csproj`는 공통 built-in 디렉터리를
   `BuiltInPets/Mongle.monglepet`으로 output과 publish에 복사한다. Debug·Release,
   packaged loose AppX와 unpackaged self-contained publish 네 경로에서 파일 누락이
   없어야 한다.
5. `App.xaml.cs`의 `LoadBundledSample()`과 `BundledSamplePath`를 의미가 분명한
   `LoadBuiltInMongle()`과 `BuiltInMonglePath`로 교체한다. built-in runtime,
   legacy 모션 cycle resolver, 활성 펫 카드와 보관함 미리보기가 모두 같은
   `LoadedPetPackage`를 사용한다.
6. `BehaviorProfileDefaults.Create()`의 설치 펫 중립 기본값은 유지하고 built-in
   전용 생성기를 별도로 둔다. `DefaultAppSettingsDocument.CreateV10()`의 최초
   built-in 프로필과 schema-v11 누락 built-in 프로필 복구만 전용 기본값을 쓴다.
7. 종전 중립 built-in 프로필과 정확히 같은 경우에만 새 권장 기본값으로
   전환한다. mode·sequence·rule·movement·petting·speech 중 하나라도 사용자가
   바꿨으면 보존한다. 설치 펫과 다른 활성 인스턴스의 프로필은 변경하지 않는다.
8. 보관함과 활성 펫 카드에는 위 메타데이터, 10개 모션과 실제 미리보기를 표시한다.
   기존 built-in key와 활성 인스턴스/profile ID는 유지한다.

공통 built-in 디렉터리의 `pet.json`은 내부 ID
`kr.mapleroom.monglepet.builtin.mongle`, 이 문서의 제작자·설명과 10개 모션을
사용한다. 외부 웹 사용자 펫 ID와 편집 marker는 넣지 않는다. `preview.png`는
150×150이며 패키지의 기존 대표 이미지를 사용하거나 `기본` 첫 프레임에서
결정적으로 생성한다. 임의 리사이즈나 효과 보정은 하지 않는다.

## Windows 앱 규칙 식별자 결정

권장 프로필의 `com.openai.codex`는 macOS 전용 값이므로 공통 JSON에 그대로
고정하지 않는다. Windows 작업 공간에서 실제 Codex 앱을 Windows 앱 선택기로
선택해 정규화된 `pfn:<package-family-name>` 또는 `exe:<file-name>` 값을 확인한다.

- packaged·unpackaged Codex가 서로 다른 식별자를 쓰면 단일 기본 규칙으로 어느
  채널을 지원할지 작업 계획의 플랫폼 차이로 결정한다.
- 확인되지 않은 PFN·전체 경로·대소문자 혼합 값을 추측해 넣지 않는다.
- 전체 실행 파일 경로, 창 제목과 문서명은 저장하지 않는다.
- 확정한 값은 자동 테스트 상수와 실제 foreground 전환 QA에서 함께 검증한다.

이 식별자 결정 전에도 자산·모션·이동·입력 없음·쓰다듬기 구현은 진행할 수 있지만,
앱 규칙을 임의 값으로 완료 처리해서는 안 된다.

## 버전과 배포 경계

공개된 Windows `1.2.0.13` 산출물을 새 자산으로 덮어쓰지 않는다. Windows 작업
계획에서 다음 Preview의 마케팅·Assembly·File·MSIX·설치기 버전을 먼저 확정하고
`WindowsDistributionTests` 기대값도 같은 변경에 갱신한다. 이번 Windows 작업은
`WINDOWS_MACOS_1_3_HANDOFF.md`의 편집기·호환성 동등성까지 모두 구현·검증한 뒤
새 GitHub Pre-release 게시와 원격 digest 검증까지 완료한다.

## 필수 자동 검증

- 10개 PNG의 SHA-256과 픽셀 크기
- 기본 모션, 모션 ID 10개, 총 36프레임, 시간과 atlas 범위
- fresh built-in 프로필의 모든 확정 옵션
- 이전 중립 기본값만 새 기본값으로 이관
- 사용자 수정 built-in 프로필 보존
- 설치 펫 기본 프로필이 종전 중립값을 유지
- settings 저장·재실행, 다중 built-in 인스턴스별 프로필 독립성
- 내장 펫 내보내기 금지와 일반 패키지 가져오기 fixture 회귀
- built-in content가 Debug·Release output, packaged loose AppX와 unpackaged publish에 모두 존재
- x64 Debug·Release 전체 테스트와 빌드

Windows 환경의 기본 검증 명령은 저장소 루트에서 다음과 같다.

```powershell
dotnet restore apps/windows/MonglePet.slnx
dotnet build apps/windows/MonglePet.slnx --configuration Debug --no-restore --maxcpucount:1
dotnet test apps/windows/MonglePet.slnx --configuration Debug --no-build --no-restore --maxcpucount:1
dotnet build apps/windows/MonglePet.slnx --configuration Release --no-restore --maxcpucount:1
dotnet test apps/windows/MonglePet.slnx --configuration Release --no-build --no-restore --maxcpucount:1
```

## 실제 Windows QA

1. 깨끗한 설정에서 몽글이가 첫 펫으로 표시되고 기본 루틴 3단계를 반복한다.
2. 포인터 접근 시 4방향 모션과 fallback이 실제 이동 방향과 일치한다.
3. 쓰다듬을 때 `해피`가 표시되고 원래 행동으로 복귀한다.
4. 60초 입력 없음에서 `자는중`, 입력 복귀 시 즉시 기본 판단으로 돌아온다.
5. 실제 Windows Codex를 전면으로 바꾸면 `일하는 중`이 적용된다.
6. 기존 수정 프로필과 다중 인스턴스를 둔 채 앱 업데이트 후 설정이 보존된다.
7. 100%·혼합 DPI 화면에서 모든 프레임이 잘리지 않고 크기·투명도가 동일하다.
8. 완료 후 `AGENTS/project/PLATFORM_PARITY.md`를 동등 상태로 갱신한다.

## 완료 조건

- 공통 built-in 데이터, Windows 네이티브 loader·기본값·이관과 UI 표시가 구현됐다.
- Debug·Release 전체 xUnit과 빌드가 통과했다.
- packaged·unpackaged 실제 앱에서 자산·행동·이동·쓰다듬기와 업데이트 보존을 확인했다.
- Windows에서 확정한 Codex 식별자로 실제 자동 규칙 전환을 확인했다.
- 기존 `ReadOnlySample.monglepet` fixture와 일반 설치 펫 동작이 회귀하지 않았다.
- `AGENTS/project/TESTING.md`, 기능 작업 계획과 `PLATFORM_PARITY.md`를 갱신했다.
- macOS·Windows 교차 결과가 확인되기 전에는 플랫폼 동등 완료로 표시하지 않는다.
