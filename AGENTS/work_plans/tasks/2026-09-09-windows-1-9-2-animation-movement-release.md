# Windows 1.9.2 애니메이션·다중 모니터 보정 Preview 릴리스

## 상태

- 상태: in_progress
- 생성일: 2026-09-09
- 마지막 갱신: 2026-09-09

## 목표

- atlas 프레임의 저장 사각형 밖 픽셀이 실행 펫과 편집 미리보기에 노출되지 않게 한다.
- 마우스 도망가기의 목적지 도착 전 평상시 전환과 혼합 해상도 모니터 사이 이동 소실·방향 떨림을 보정한다.
- 검증된 Windows `1.9.2.24`를 새 미서명 x64 Preview로 게시한다.

## 범위

- runtime atlas visual clip과 편집기 공통 캔버스 clip
- 도망 목적지 유지와 범위 밖 포인터의 목적지 재계산 제한
- 모니터 공유 경계를 이용하는 화면 전환 geometry
- geometry·WinUI source contract 회귀 테스트
- 버전, 설치기, GitHub Pre-release와 배포 문서

## 제외 범위

- settings schema-v16, 제작자 설정 schema-v12와 `.monglepet` formatVersion 변경
- 모니터 배치 UI와 이동 방식 설정 변경
- 코드 서명, 자동 업데이트와 macOS 소스 변경

## 열린 질문

- 없음

## 결정사항

- 기존 `1.9.1.23` 자산을 보존하고 patch 버전 `1.9.2.24`, 태그 `windows-v1.9.2-preview.1`을 사용한다.
- 모니터 전환은 가상 화면 전체 사각형이 아니라 실제 work area가 공유하는 경계를 통해서만 진행한다.
- 도망 목적지는 포인터가 해제 거리 밖으로 나가도 도착까지 유지하되 범위 밖 포인터 이동으로 다시 만들지 않는다.

## 작업 순서

### Windows

- [x] atlas frame·편집 미리보기 clip 구현과 테스트
- [x] 도망 종료와 혼합 해상도 화면 경유 구현과 테스트
- [x] 실제 설치본에서 사용자 이동 QA
- [x] 앱 버전을 `1.9.2.24`로 갱신
- [x] Debug·Release 전체 빌드와 테스트 재검증
- [x] 미서명 x64 설치기 생성과 업데이트 설치 검증
- [ ] 기능 커밋·태그·GitHub Pre-release 게시
- [ ] 원격 자산 digest와 태그 대상 검증

### 플랫폼 동등성

- [ ] Windows에서 편집·저장한 atlas의 macOS 실제 왕복 확인
- [ ] 추가 혼합 DPI·세로 배치 모니터 QA

## 검증 방법

- `dotnet build apps/windows/MonglePet.slnx --configuration Debug --no-restore --maxcpucount:1`
- `dotnet test apps/windows/MonglePet.slnx --configuration Debug --no-build --no-restore --maxcpucount:1`
- 같은 Release 빌드·테스트
- `git diff --check`
- 기존 설치 위 업데이트, 설치 DLL/publish DLL 해시 일치와 실행 응답 확인
- GitHub에서 설치기·체크섬을 다시 내려받아 로컬 SHA-256과 비교

## 진행 로그

- 2026-09-09: atlas clip, 도망 목적지 유지와 실제 `2560×1392`·`1920×1032` work area의 공유 경유 geometry를 구현했다.
- 2026-09-09: 첫 경유 구현에서 경계 진입 뒤 staging으로 되돌아가는 방향 떨림을 사용자 QA로 확인하고, 전환 segment 안에서는 bridge 방향을 유지하도록 보정했다.
- 2026-09-09: 보정 후 Debug·Release 각 384개 테스트와 경고·오류 없는 전체 빌드가 통과했고 설치 DLL 일치·실행 응답과 사용자 실제 이동 확인을 마쳤다.
- 2026-09-09: `1.9.2.24` 설치기는 65,320,218 bytes, SHA-256 `50FA9B1923D1191C7BF07CF8B3E66267A46AA3383EC953F9C7CEA746E22A1AE4`다. 기존 설치 위 업데이트에서 사용자 데이터 127개·50,013,147 bytes와 inventory digest를 그대로 보존하고 설치 DLL/publish DLL 일치와 실행 응답을 확인했다.

## 완료 결과

- 게시 완료 뒤 갱신한다.

## 남은 위험 / 후속 작업

- 실제 세로 배치·세 대 이상 모니터와 100%·150%·200% 혼합 DPI 조합은 추가 QA가 필요하다.
- macOS에서 Windows가 저장한 atlas 패키지의 실제 왕복은 남아 있다.
