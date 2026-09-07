# Windows 펫 내보내기 용량·무손실 최적화 인계

## 목적

macOS D-129에서 확정한 공유 패키지 용량 안내, 내보내기 전용 PNG 무손실 최적화와 오류 표시를 Windows WinUI 3 앱에 동등하게 반영한다. Windows 소스 변경·빌드·실제 QA는 Windows 환경에서 진행한다. 설치된 펫과 사용자가 제작한 원본 자산을 절대 재인코딩하지 않는다.

## 먼저 확인할 기준

- 제품 결정: `AGENTS/project/DECISIONS.md`의 D-129·D-130
- 공통 계약: `AGENTS/specifications/PET_PACKAGE.md`의 `로컬 공유 내보내기`
- macOS 기준 구현:
  - `apps/macos/MonglePet/PetLibrary/PNGExportOptimizer.swift`
  - `apps/macos/MonglePet/PetLibrary/PetPackageExporter.swift`
  - `apps/macos/MonglePet/PetLibrary/PetPackageSharingService.swift`
  - `apps/macos/MonglePet/SettingsView.swift`
- Windows 현재 구현: `apps/windows`의 package exporter, 공유 검토 dialog와 `내 펫` card 내보내기 진입점

## 확정 사용자 결과

1. `내 펫 > 패키지로 내보내기`의 검토 화면에서 미리보기와 atlas PNG의 현재 합계를 표시한다.
2. `애니메이션별 용량 자세히 보기`처럼 접힌 목록에서 대표 이미지와 atlas를 사용하는 애니메이션 이름·크기를 큰 순서대로 확인할 수 있어야 한다.
3. 표시한 값은 최적화 전 PNG 자산 합계이며 최종 ZIP 예상값으로 오해시키지 않는다.
4. 저장을 확정하면 설치된 펫을 그대로 두고 내보내기 staging의 PNG만 무손실 최적화한다.
5. 준비 시간이 걸리는 동안 `내 펫` 문맥에 진행 상태를 표시하고 설정 창의 UI thread를 막지 않는다.
6. 최적화·30 MiB·파일 저장 오류는 `펫 정보·애니메이션`의 일반 오류 영역이 아니라 사용자가 시작한 `내 펫` 내보내기 문맥의 dialog 또는 InfoBar로 표시한다.
7. 최적화 뒤에도 30 MiB를 초과하면 기존 제한 오류를 명확히 표시하고 설치 원본과 기존 목적지 파일을 보존한다.
8. 같은 이미지를 다시 내보낼 때는 안전한 캐시를 사용하고, 이미지가 변경되면 해당 이미지만 다시 최적화한다.
9. 저장 성공 안내에는 실제 완성된 `.monglepet` 파일 용량을 표시한다.

## Domain·내보내기 경계

- D-130: 상한을 정확히 31,457,280 bytes로 바꾼다. archive extractor 기본값, remote import metadata 사전 검사, Content-Length·실제 수신 크기, exporter·공유 검토 UI·오류 문구·테스트를 모두 30 MiB로 일치시킨다.
- 구버전 앱은 20 MiB 초과를 거부한다. 양 플랫폼 지원 배포와 웹 업데이트 안내를 준비한 뒤 서버 상한을 전환한다. 첫 지원 릴리스 번호는 배포 시 확정하고 schema를 대신 올리지 않는다.
- exporter는 설치 폴더를 직접 수정하거나 그대로 압축하지 않는다. 기존처럼 별도 staging을 만들고 canonical manifest, preview, 참조 atlas와 제작자 설정만 구성한다.
- PNG optimization 함수의 입력은 원본 bytes이고 출력은 새 bytes다. 원본 URL에 쓰거나 편집 저장·애니메이션 수정 시 호출하지 않는다.
- 최소 지원 범위는 non-interlaced 8-bit PNG다. Windows decoder/encoder로 더 넓은 형식을 안전하게 지원해도 되지만 디코딩 결과 비교 없이 결과를 채택하면 안 된다.
- 최적화 후보는 원본과 다음이 모두 같아야 한다.
  - width와 height
  - RGBA 픽셀 전체 또는 동일한 완전 디코딩 표본
  - 알파 값
- 후보 바이트 수가 원본보다 작을 때만 사용한다. 디코딩·최적화·검증 실패 또는 결과 증가 시 원본 PNG bytes를 staging에 복사한다.
- atlas의 셀, frame 좌표, frame 수·순서, 해상도와 canvas 배치를 바꾸지 않는다. 빈 셀 제거와 atlas 재배치는 별도 기능이다.
- staging을 package loader로 다시 읽고 ZIP round trip 검증을 통과한 뒤에만 목적지 파일을 원자적으로 교체한다.
- 완성 ZIP의 30 MiB 상한과 expanded 100 MiB 등 기존 보안 제한은 유지한다.

## 캐시 계약

- key는 최소 `SHA-256(original PNG bytes) + optimizer implementation version`을 포함한다.
- optimizer version은 필터 선택·encoder 옵션이 바뀔 때 반드시 변경한다.
- cache hit도 파일이 원본보다 작은지와 디코딩 픽셀 동일성을 다시 확인한다. 손상 캐시는 버리고 다시 계산하거나 원본으로 복구한다.
- 캐시는 `%LOCALAPPDATA%` 아래 앱 전용 cache 위치에 두고 installation 폴더, settings, `.monglepet` 안에는 넣지 않는다.
- 캐시 상한은 macOS 기준 256 MiB이며 초과 시 오래된 regular file부터 정리한다. 정리 실패는 내보내기 성공을 막지 않는다.
- 사용자가 펫을 편집해 원본 PNG bytes가 바뀌면 hash가 달라져 자동으로 기존 cache를 사용하지 않는다.

## WinUI 변경

- 공유 검토에 `공유 파일 용량` group을 둔다.
- 첫 행은 `현재 이미지`와 IEC 단위 `MiB`를 표시한다. preview와 각 atlas를 한 번씩만 합산한다. 한 atlas를 여러 animation이 참조해도 중복 계산하지 않는다.
- 현재 PNG 합계가 30 MiB보다 크면 `저장할 때 설치된 펫은 그대로 두고 내보내기 임시 사본만 무손실 최적화합니다.`를 강조한다.
- 세부 목록 label은 대표 이미지 또는 atlas를 참조하는 animation display name을 사용한다. 내부 atlas ID와 로컬 경로를 사용자에게 노출하지 않는다.
- 사용자가 권리 확인과 저장을 확정하면 dialog를 닫고 비동기 준비 상태를 `내 펫` 화면에 표시한다. 완료 뒤 FileSavePicker를 연다.
- 작업 중 같은 펫의 중복 내보내기·삭제처럼 충돌 가능한 동작을 잠시 막되 설정 창 전체 message pump를 차단하지 않는다.
- 실패 메시지는 내보내기 시작 화면에 표시하고, 다른 설정 목적지로 이동해야 볼 수 있는 공용 오류 label에만 기록하지 않는다.

## 필수 자동 테스트

1. 최적화 전후 PNG의 width·height와 전체 RGBA 픽셀이 같다.
2. 작은 후보만 채택하고 결과 증가·지원하지 않는 PNG·손상 결과는 원본으로 복구한다.
3. 내보낸 package를 다시 가져왔을 때 모든 frame pixel과 manifest frame 좌표가 같다.
4. export 전후 설치 preview·atlas의 bytes, 해시와 수정 시간이 바뀌지 않는다.
5. 첫 내보내기는 cache miss, 같은 source 두 번째 내보내기는 cache hit다.
6. source 한 바이트 변경과 optimizer version 변경은 cache를 무효화한다.
7. 손상 cache는 사용하지 않으며 내보내기를 안전하게 다시 수행한다.
8. preview와 atlas별 크기 합계가 정확하고 공유 atlas는 한 번만 계산한다.
9. 30 MiB 아래·경계·최적화 후 아래·최적화 후에도 위인 package 결과를 검증한다.
10. 실패 시 기존 목적지 파일, source installation과 제작자 설정이 유지된다.
11. 준비 작업이 UI thread 밖에서 실행되고 WinUI 입력·창 이동이 응답 가능한지 adapter test로 확인한다.
12. 기존 canonical files, 제작자 설정 v12와 package 보안·round trip 테스트를 모두 통과한다.

## 실제 Windows QA

- 큰 펫에서 공유 검토의 총 PNG와 세부 목록이 실제 파일 합계와 맞는지 확인한다.
- 첫 내보내기 중 설정 창 이동·스크롤이 멈추지 않고 진행 안내가 `내 펫`에 보이는지 확인한다.
- 같은 펫을 연속 두 번 내보내 두 번째 준비가 빨라지는지 확인한다.
- 애니메이션 하나를 편집한 뒤 해당 atlas만 다시 처리되고 다른 자산 캐시는 재사용되는지 확인한다.
- 내보낸 펫의 모든 animation과 알파 경계가 원본과 시각적으로 같은지 확인한다.
- 30 MiB를 계속 넘는 fixture에서 오류 위치·문구, source와 기존 목적지 보존을 확인한다.
- macOS 내보내기 → Windows 가져오기와 Windows 내보내기 → macOS 가져오기에서 package와 제작자 설정을 비교한다.

## 변경하지 않을 항목

- `.monglepet` formatVersion
- settings schema-v16과 제작자 설정 schema-v12
- expanded 100 MiB·64 MiPixels·2,000 entries·100:1 등 압축 파일 크기 이외의 보안 상한
- PNG atlas 배치와 frame 좌표
- WebP 자동 변환이나 손실 압축
- Windows 앱 버전·빌드 번호와 Release

## 완료 보고

- Windows optimizer·cache와 exporter staging 구조
- 공유 검토 용량 UI와 오류 전달 경로
- 원본 불변·픽셀 동일성·fallback 검증 결과
- 자동 테스트 통과 개수와 Debug·Release 빌드
- 실제 Windows QA와 macOS 교차 왕복
- 남은 위험, git status와 커밋·푸시 상태

Windows 구현과 실제 QA가 끝나기 전에는 `PLATFORM_PARITY.md`를 동등 완료로 바꾸지 않는다.

## 서버 인계

서버 설정·검증·공개 순서는 `WEB_COMMUNITY_HANDOFF.md`의 D-130 절을 따른다. 문서 갱신만으로 실제 운영 서버나 Windows 구현이 반영된 것은 아니다.
