# MonglePet Shared Resources

macOS와 Windows 구현이 함께 사용하는 데이터 규격의 검증 자료를 둔다.

현재 공유 항목:

- `Samples/`: `.monglepet` 가져오기·호환성 수동 검증 샘플
- `Fixtures/Settings/`: 플랫폼 공통 설정 마이그레이션 입력과 기대 결과

설정 fixture의 UUID는 테스트 재현을 위한 고정값이며 실제 앱은 새 UUID를 생성한다. 실행 코드, UI 코드, 실제 사용자 화면 좌표와 운영체제별 앱 식별자는 이 디렉터리에서 공유하지 않는다.

신규 기능은 macOS에서 먼저 검증하되 공통 데이터가 달라지면 같은 작업에서 이 디렉터리의 fixture와 루트 명세를 갱신한다. Windows 적용 시 같은 fixture를 읽고 쓴 결과를 비교해 기능 동등성을 확인한다.
