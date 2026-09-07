# 무손실 WebP 내보내기 공통 fixture (D-131)

실제 사용자 펫이 아닌 결정론적 합성 RGBA 이미지다. `WebPExportFixture.png`와 `WebPPackageExportTests.testExportImportEditAndReexportPreservesFramesProfileAndOriginal`이 macOS libwebp 1.6.0으로 생성했다. 생성 테스트에 `TEST_RUNNER_MONGLEPET_WEBP_QA_FIXTURE_DIRECTORY=<비어 있는 임시 디렉터리>`를 전달하면 새 결과를 얻을 수 있다. ZIP의 시각 정보 때문에 재생성한 archive SHA-256 자체는 달라질 수 있다.

## 파일과 기대값

- `source/`: 입력 PNG 디렉터리 패키지. atlas는 128×128, alpha 0·128·255와 완전 투명 픽셀의 유색 RGB를 포함한다.
- `lossless-webp.monglepet`: macOS 실제 exporter 결과, 2,231 bytes. SHA-256 `c2bcaebfc678313ec7d6511021068dae68c3efd4532e578e98a246db9a56e810`.
- 원본 `source/assets/_monglepet_webp/source.png` SHA-256: `c89a0caf744d2de377456db5d610507a78c94d9c7066564a9cf2c19e01505c31`.
- 출력 atlas `assets/_monglepet_webp_1/0.webp`는 정적 무손실 WebP다. 원래 디렉터리명 충돌을 피한 결과다. atlas ID는 `main`, preview는 16×16 PNG다.
- `idle` 프레임: `(0, 0, 64, 128)` 450 ms, `(64, 0, 64, 128)` 275 ms. 순서·크기·시간은 입력과 같다.
- 패키지 formatVersion 1, 제작자 설정 schemaVersion 12, 최소 앱 1.7.0. 입력에는 없는 제작자 설정을 테스트가 명시적으로 내보내기에 전달했다. 평상시 fixed `default` 행동, idle 2회 단계, 이동 fixed·크기 100%·투명도 100%·말풍선 비활성이다.

## 각 플랫폼 확인

1. 원본 PNG와 출력 WebP의 straight RGBA를 비교한다. alpha 0 픽셀의 RGB까지 동일해야 한다. premultiplied 비교만으로 이 조건을 대체하지 않는다.
2. 실제 앱/브라우저 decoder에서 sRGB 렌더링, 프레임 crop, 알파와 프레임 시간을 확인한다.
3. 가져오기 → 기존 프레임 그대로 애니메이션 편집 저장 → 재내보내기 → 다시 가져오기를 수행하고 프레임 렌더링·시간·설정 보존을 확인한다. 재편집기가 PNG를 만드는 것은 정상이며 압축 바이트의 동일성은 요구하지 않는다.
4. 서버 업로드 → 격리 검증 → 파생 미리보기 → 다운로드를 확인한다. 원본 다운로드 SHA-256은 위 값과 같아야 한다.
5. 각 플랫폼 codec 버전·실제 OS·QA 결과를 인계 문서에 남긴다. 작은 합성 이미지 통과가 대형 펫의 성능 검증을 대체하지는 않는다.

macOS 자동 왕복 검증 자료이며 Windows·웹 실기 QA 완료를 의미하지 않는다. 앱의 Release 기본 WebP 활성화는 별도 승인 단계다.
