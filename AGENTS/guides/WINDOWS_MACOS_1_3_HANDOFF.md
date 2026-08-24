# Windows 인계: macOS 1.3 펫 호환성·이미지 편집기

## 목적과 시작 조건

macOS `1.3.0 (5)`에서 확정한 펫 버전 정책, 최소 앱 버전 권장 안내, PNG·스프라이트 편집 결과와 새 내장 몽글이 및 공개 뒤 이미지 편집 UI 보정을 Windows 네이티브 앱에 반영한다. Windows 소스·빌드·실제 QA는 Windows 작업 공간에서만 수행한다.

작업 전 `AGENTS.md`, `apps/windows/AGENTS.md`, 이 문서, `AGENTS/specifications/PET_PACKAGE.md`, `AGENTS/project/DECISIONS.md`의 D-086~D-089, `AGENTS/guides/WINDOWS_BUILTIN_MONGLE_HANDOFF.md`, `AGENTS/project/PLATFORM_PARITY.md`를 읽는다. 태그 `macos-v1.3.0-preview.1`뿐 아니라 이 문서의 공개 뒤 편집 보정까지 포함한 최신 `main`을 `pull --ff-only`한 뒤 별도 Windows 작업 계획을 만든다.

## 공통 계약

### 버전

- `pet.json`의 최상위 `version`은 비어 있지 않은 펫 콘텐츠 자유 문자열이다. 한글·영문을 허용하고 SemVer 분석·정렬·자동 승격을 하지 않는다.
- `compatibility.createdWithMonglePetVersion`, `minimumMonglePetVersion`과 웹 `minimum_app_version`만 엄격한 `MAJOR.MINOR.PATCH`다.
- 최소 앱 버전이 현재 앱보다 높아도 파일 크기·SHA-256·archive·manifest·이미지·권장 프로필 검증을 통과하면 설치할 수 있다.
- 검토 화면에는 업데이트 권장, 일부 기능이 적용되지 않거나 다르게 보일 수 있다는 설명과 `https://mapleroom.kr/monglepet/download` 버튼을 표시한다.
- 지원하지 않는 `formatVersion`, 잘못된 숫자형 호환 버전, 손상·과대·안전하지 않은 패키지는 계속 차단한다.
- 업데이트 가능 여부 조회와 자동 업데이트는 보류다. 다운로드 페이지 열기 외에 새 버전 조회·자동 다운로드·설치 네트워크 로직을 넣지 않는다.

Windows의 `RemotePetImportService.cs`는 현재 더 높은 최소 앱 버전을 `MinimumAppVersionRequired`로 다운로드 전에 차단한다. 이를 게시 최소 버전을 보존하는 비차단 advisory 결과로 바꾸고, 패키지 manifest 값과 게시 값 중 더 높은 값을 검토 UI에 표시한다. 로컬 `PetPackageImporter`와 웹 임시 세션은 같은 사용자 결과를 가져야 한다.

### 이미지 출력

- 최종 픽셀 순서는 `원본 crop → 좌우·상하 뒤집기 → 공통 캔버스 배치 → atlas PNG`다.
- flip·crop·확대 편집 이력은 schema에 추가하지 않고 최종 atlas 픽셀에 굽는다.
- 확대는 화면 표시만 바꾸며 crop의 원본 좌상단 픽셀 좌표를 바꾸지 않는다.
- 미리보기와 저장은 같은 crop·flip 처리 경로를 사용해야 한다.
- 새 프레임 간격 기본값은 모든 생성·추가·수정 경로에서 `450ms`, 허용 범위는 `16...60,000ms`다.

## macOS 기준 UI와 Windows 구현 결과

SwiftUI를 복사하지 말고 WinUI 3 네이티브 컨트롤로 아래 정보 구조와 결과를 맞춘다. 현재 `PetAnimationEditorControl.xaml`은 단순 목록과 균등 행·열 dialog, `120ms` 기본값만 제공하므로 별도 crop/selection editor와 preview 모델이 필요하다.

### 공통 애니메이션 편집 화면

- 상단 `애니메이션 설정`: 이름, 새 프레임 간격, 반복 재생.
- 본문 왼쪽: 현재 프레임과 전체 애니메이션 미리보기, 공통 캔버스 위치·크기 편집과 첫 프레임 반투명 비교.
- 본문 오른쪽: 최종 프레임 순서, 썸네일, 개별 간격, 위·아래 이동, `프레임 복사`, 삭제.
- 복사는 이미지 source/crop·flip이 적용된 픽셀, 간격과 캔버스 배치를 유지한 새 독립 항목을 바로 다음 위치에 넣고 선택한다.
- `프레임 추가`는 `개별 PNG 추가…`와 `스프라이트 시트에서 추가…`를 명확히 구분한다.

### PNG crop 편집기

- 여러 PNG를 한 번에 열고 Windows 표준 다중 선택으로 함께 미리보기·일괄 편집한다.
- 목록 선택은 가져오기 포함 여부가 아니라 집중/일괄 편집 대상이다. 목록의 모든 PNG를 최종 추가한다.
- 집중 원본은 경계 내부 이동, 8방향 크기 조절, X·Y·너비·높이 숫자 입력, 투명 여백 자동 맞춤과 원본 전체 복원을 제공한다.
- `PNG 더 추가…`로 dialog를 닫지 않고 새 PNG를 append하며 기존 draft를 보존한다.
- 1×~8× 확대·축소·맞춤과 scroll/pan을 제공한다. 확대 중에도 원본 픽셀 좌표와 drag 안정성을 유지한다.
- 좌우·상하 뒤집기는 현재 선택 묶음에 적용하고 최종 crop 미리보기에 즉시 반영한다.
- 단일 PNG도 원본 자르기 캔버스와 별도로 `잘라낸 결과 미리보기`를 항상 표시한다. 결과 패널은 오른쪽 상단에 고정하고 여러 PNG를 선택하면 이전·다음 버튼으로 선택 순서의 집중 대상을 바꾼다.
- 결과 미리보기는 애니메이션 프레임 미리보기와 같은 10px 투명 격자, 바깥 캔버스 테두리와 실제 crop 전체 픽셀 범위의 파란 실선을 사용한다. 투명 여백도 파란 경계 안에 포함한다.
- 편집 dialog의 header와 footer, 왼쪽 원본 자르기 캔버스와 오른쪽 결과 패널은 고정한다. 선택 범위와 PNG 목록만 결과 아래에서 독립적으로 스크롤해 최소 창 높이에서도 `PNG 더 추가…`와 모든 일괄 작업에 접근할 수 있어야 한다.
- PNG 목록은 각 항목의 현재 crop 썸네일과 집중 항목의 파란 강조 경계를 표시한다. 별도 하단 다중 결과 목록은 만들지 않아 편집과 결과 확인 사이의 세로 왕복을 없앤다.

### 스프라이트 시트 편집기

- 전체 시트에서 `프레임 선택`과 `범위 편집` 모드를 분리한다.
- 자동 제안 또는 1~32 행·열 균등 격자에서 시작하고 각 경계를 독립 이동·8방향 크기 조절·숫자 입력한다.
- `읽기 순서`와 선택을 비운 뒤 누른 순서로 번호를 정하는 `클릭 순서`를 제공한다.
- 선택 영역 crop 미리보기는 시트의 포함/제외 클릭과 분리한다. 최종 선택 순서의 이전·다음 버튼과 미리보기 클릭으로만 탐색한다.
- 선택 영역도 PNG 결과와 같은 투명 격자·바깥 테두리·파란 crop 프레임 경계를 표시해 투명 여백과 저장 크기를 구분한다.
- 전체 시트 캔버스 높이는 원본 종횡비와 dialog의 현재 가용 높이에 맞추되 최소 편집 높이를 보장한다. 가로로 긴 시트를 고정 높이 viewport에 넣어 위·아래 빈 공간을 크게 만들지 않는다.
- 선택 영역 미리보기는 오른쪽 상단에 고정하고, 경계 설정·선택 범위·프레임 순서·배경만 그 아래 독립 세로 ScrollViewer에 둔다. 설정 항목이 길어져도 선택 결과·이전/다음·flip 버튼이 화면 밖으로 밀리지 않아야 한다.
- 현재 미리보기 프레임에 좌우·상하 뒤집기를 독립 적용한다.
- 전체 시트도 1×~8× 확대·축소·맞춤과 scroll/pan을 제공한다.
- 배경 제거 미리보기, 선택 crop 미리보기와 최종 추출은 같은 처리된 source를 사용한다.

### 성능·안정성

- 투명 픽셀 경계는 원본당 한 번 분석해 cache한다.
- drag 중 전체 PNG 또는 전체 atlas를 매 포인터 이벤트마다 다시 디코딩·합성하지 않는다. 고정 좌표의 overlay만 갱신하고 확정 시 필요한 결과를 만든다.
- 확대 콘텐츠의 scroll 좌표와 crop drag 좌표를 분리해 핸들이 튀거나 영역이 포인터를 뒤늦게 따라오지 않게 한다.
- 1× 맞춤에서는 이미지 내부 ScrollViewer가 세로 wheel을 소비하지 않고 dialog 본문이 스크롤한다. 1×보다 클 때만 이미지 viewport의 가로·세로 pan을 활성화한다. 확대 영역 위에서 바깥 본문으로 이동할 수 있는 키보드·스크롤 대안도 유지한다.
- 확대·축소 버튼은 같은 30×24pt 기준 hit area, 같은 12×12pt 아이콘 frame과 같은 border style을 사용해 `+`·`−`의 실제 높이와 정렬을 맞춘다. Windows에서는 DPI 독립 단위로 같은 시각 결과를 구현한다.
- 취소 시 임시 파일·draft를 제거하고 설치·보관함·기존 프레임을 바꾸지 않는다.

## 새 내장 몽글이

`shared/BuiltInPets/Mongle.monglepet/`가 플랫폼 공통 데이터 기준본으로 이미 저장소에 있다. Windows에서 새 디렉터리를 만들거나 `apps/macos` 자산을 복사하지 말고 이 기준본을 output/publish에 포함한다. 자세한 loader·설정 이관·Codex 규칙·QA는 `WINDOWS_BUILTIN_MONGLE_HANDOFF.md`를 따른다.

공통 `recommended-profile.json`은 플랫폼 전용 앱 식별자를 의도적으로 제외한다. Windows 앱 선택기로 실제 Codex의 정규화된 `pfn:` 또는 `exe:` 값을 확인해 built-in 전용 기본 프로필에만 추가한다.

## 자동 테스트

- 펫 콘텐츠 버전 `봄 에디션`, `release-A`가 보존되고 자동 승격·SemVer 비교되지 않는다.
- 로컬·웹 최소 앱 버전 9.0.0 패키지가 advisory와 다운로드 버튼을 표시하고 명시적 설치 후 정상 등록된다.
- 잘못된 호환 버전, 미래 `formatVersion`, archive traversal·symlink·20MiB·digest mismatch는 계속 거부된다.
- 비대칭 RGBA fixture의 crop, 좌우, 상하, 양축 flip 픽셀이 macOS와 같은 위치다.
- 확대 배율이 달라도 저장 crop 좌표가 같다.
- 1×에서는 내부 pan이 비활성이고 확대 배율에서만 활성인 viewport 정책을 검증한다.
- 가로·세로·정사각 결과가 격자 캔버스 안에 inset을 두고 aspect-fit되어 파란 경계가 잘리지 않는다.
- 가로로 긴 전체 시트는 최소 높이까지 축소되고 세로로 긴 시트는 현재 viewport 높이를 넘지 않는지 검증한다. 설정 ScrollViewer를 끝까지 이동해도 고정 선택 영역 미리보기가 계속 보이는지 확인한다.
- PNG 추가 전후 기존 crop·flip·순서 보존, 다중 일괄 flip, 취소 무변경.
- 스프라이트 `4→1→3` 클릭 순서, 선택 제거 재번호, 서로 다른 frame별 flip, crop 미리보기와 최종 atlas 일치.
- 프레임 복사가 source·duration·placement를 보존하고 새 독립 ID로 바로 다음에 삽입된다.
- 모든 새 프레임 진입점이 450ms이고 기존 저장 간격은 바뀌지 않는다.
- 공통 built-in 10개 PNG digest·크기, 10개 모션·36프레임과 기본 프로필 이관 회귀.
- x64 Debug·Release 전체 테스트와 빌드, packaged loose AppX·unpackaged publish 콘텐츠 확인.

## 실제 Windows QA와 완료 조건

1. 운영 펫 상세 URL과 로컬 패키지에서 높은 최소 버전 경고 뒤 설치·권장 설정 적용·중복 처리를 확인한다.
2. 다운로드 페이지 버튼이 정확한 운영 URL을 기본 브라우저로 열며 앱이 백그라운드 업데이트 조회를 하지 않는지 확인한다.
3. 작은 PNG와 7×8 불규칙 시트를 4× 이상 확대해 crop drag·resize·scroll 안정성과 미리보기 일치를 확인한다. 최소 창 높이에서 PNG 설정만 끝까지 내려 `PNG 더 추가…`, 목록과 일괄 작업에 접근하고, 스크롤 전후에도 오른쪽 결과 패널과 footer가 계속 보이는지 확인한다.
4. PNG 추가, 다중 선택 flip, 스프라이트 frame별 flip, 복사·순서·간격·배치를 저장하고 내보낸다.
5. Windows 결과를 macOS에서 가져와 atlas 픽셀·frame 순서·duration·표시 크기가 같은지 교차 확인한다.
6. packaged/unpackaged에서 새 built-in, 기존 수정 프로필 보존, Codex 규칙, 도망가기·쓰다듬기와 업데이트 설치를 확인한다.
7. 키보드, Narrator, 100%·150%·200% DPI에서 `+`·`−` 버튼 높이·초점 사각형, 결과 경계 대비와 중첩 ScrollViewer를 확인하고 큰 이미지 반복 drag의 CPU·메모리·응답성을 측정한다.

Windows 전체 구현·실제 QA와 교차 왕복 전에는 `PLATFORM_PARITY.md`를 완료로 바꾸지 않는다. Windows Preview 버전은 공개 `1.2.0.13`을 덮어쓰지 않고 별도 버전으로 올리며, 사용자 요청대로 모든 구현·검증이 끝난 뒤 새 GitHub Release를 게시한다.
