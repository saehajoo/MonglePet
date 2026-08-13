# Settings Fixtures

macOS와 Windows가 같은 설정 스키마 변환 결과를 만드는지 검증한다.

- `schema-v10-single-pet.json`: 한 설치 펫과 프로필을 가진 기존 입력
- `schema-v11-single-instance.expected.json`: 고정 instance/profile UUID를 사용한 v11 기대 결과

v10→v11 UUID 생성 순서는 첫 활성 인스턴스, 저장된 행동 프로필 순서다. fixture의 UUID는 테스트 전용이며 실제 사용자 설정에 재사용하지 않는다.
