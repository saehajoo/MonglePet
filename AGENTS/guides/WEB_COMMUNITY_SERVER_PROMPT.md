# 웹 커뮤니티 서버 구현 전달 프롬프트

아래 프롬프트는 별도 웹 커뮤니티 저장소를 담당하는 Codex나 개발자에게 그대로 전달한다. 실제 기술 스택, 개인 서버 구성과 기존 인증 환경을 먼저 조사한 뒤 구현 계획을 확정한다.

---

MonglePet 펫 공유 커뮤니티의 서버와 웹 UI를 별도 Git 저장소에서 설계·구현해 주세요.

먼저 MonglePet 저장소에서 다음 계약 문서를 읽고, 사용한 원본 Git commit과 schema 버전을 서버 저장소 문서에 기록해 주세요.

- `AGENTS/guides/WEB_COMMUNITY_HANDOFF.md`
- `AGENTS/specifications/PET_PACKAGE.md`
- `AGENTS/project/DECISIONS.md`의 D-060, D-061
- `AGENTS/project/DECISIONS.md`의 D-120
- `shared/`의 정상·오류·악성 fixture

현재 데스크톱 계약은 로컬 설정 schema-v16, `recommended-profile.json` schema-v12다. 서버의 업로드 검사 JSON Schema와 validator가 v1~v12를 허용하고 v12의 자유 이동 `dwellMode: fixed | random | behaviorCompletion`을 검증하도록 갱신하세요. 이 변경은 PetVersion DB 컬럼을 요구하지 않으며 원본 패키지를 immutable object로 보존하는 기존 모델을 유지합니다. 서버가 제작자 설정을 검색용 구조로 별도 추출하고 있다면 그 파생 DTO·색인 schema만 함께 갱신하세요.

## 제품 범위

- 비회원: 펫 목록, 검색, 상세, 버전 목록, 미리보기와 `.monglepet` 다운로드
- 로그인 사용자: 펫 업로드, 자신의 펫 새 버전 등록, 댓글, 좋아요와 신고
- 관리자: 업로드 검토, 승인·반려, 숨김, 신고 처리와 삭제 요청 대응
- 원본 `.monglepet`은 비공개 quarantine에서 검증한 뒤 승인된 immutable object만 공개
- 웹용 미리보기는 검증된 원본에서 별도 파생하고 원본 패키지를 브라우저에서 직접 실행하지 않음

## 펫 라이선스 정책

- 펫별 라이선스 입력란, 선택 UI, 공개 표시, 검색 필터와 문자열 판별을 구현하지 마세요.
- schema-v1의 기존 `pet.json.license`가 존재할 수 있지만 이는 레거시 호환 필드입니다.
- `license`가 없다고 업로드를 거부하지 말고, 값이 있어도 DB 공개 metadata나 게시 허용 판정에 저장·사용하지 마세요.
- 새로 정규화하거나 다시 내보내는 manifest에는 `license`를 쓰지 마세요.
- 대신 업로드마다 로그인한 사용자가 해당 펫과 이미지 자산을 게시할 권한이 있음을 체크박스로 확인하게 하세요.
- 확인 시각, 사용자 ID, 약관 버전과 요청 IP에 대한 보관 필요성은 개인정보 최소화 원칙으로 별도 검토하세요.
- 신고, 임시 숨김, 삭제 요청, 반복 위반자 제재와 관리자 검토 절차를 구현하세요.
- 이 정책은 MonglePet 소스 코드의 PolyForm Noncommercial License나 제3자 고지를 제거한다는 뜻이 아닙니다.

## 식별자와 소유권

- `pet.json.id`인 package ID는 펫 정의의 안정적인 식별자이지만 소유권 증명이 아닙니다.
- 서버는 별도의 `Pet UUID`, `PetVersion UUID`, 공개 slug와 인증된 owner user ID를 생성하세요.
- 최초 업로드가 승인되면 서버 Pet과 owner 관계를 만들고, 새 버전 추가는 해당 owner만 수행하게 하세요.
- 새 버전은 기존 Pet endpoint를 통해 등록하고 package ID 일치를 검사하되 package ID만으로 권한을 부여하지 마세요.
- 편집 가능한 사본은 MonglePet에서 새로운 package ID를 받으므로 기본적으로 독립 Pet으로 처리하세요.
- 추후 리믹스 관계가 필요하면 서버의 선택적 `derivedFromPetID`를 사용하고 클라이언트 문자열만으로 관계를 확정하지 마세요.
- 게시된 PetVersion의 원본 object와 SHA-256은 변경하지 말고 수정 파일은 새 PetVersion으로 등록하세요.

## 최소 데이터 모델

- User: 서버 UUID, 인증 subject, 공개 프로필, 역할과 상태
- Pet: 서버 UUID, slug, package ID, owner user ID, 공개 이름·설명·태그, 대표 버전, 게시 상태와 시각
- PetVersion: 서버 UUID, Pet ID, 패키지 version, formatVersion, 앱 호환 버전, 제작자 snapshot, object key, SHA-256, 크기, 미리보기 metadata, 검증 결과와 상태
- Comment, Like, Report, Tag와 관리자 감사 기록
- Pet과 PetVersion에 펫 라이선스 컬럼을 추가하지 마세요.

## 업로드 보안

- presigned upload 또는 제한된 업로드 endpoint를 사용하고 확장자·전체 압축 크기 상한을 먼저 적용하세요.
- ZIP 엔트리 수, 개별·전체 해제 크기, 압축률, 중복·대소문자 충돌, 절대경로, `..`, 심볼릭 링크와 실행 파일을 검사하세요.
- 격리된 임시 공간에 허용 엔트리만 개별 해제하세요.
- `pet.json`, 선택적 `recommended-profile.json`, PNG·정적 WebP, 픽셀 크기, 알파, 프레임 영역과 시간을 MonglePet 계약과 동일하게 검증하세요.
- `recommended-profile.json` schema-v12의 `freeRoaming.dwellMode`와 `cursorAvoiding.idleFreeRoaming.dwellMode`는 `fixed`, `random`, `behaviorCompletion`만 허용하세요. v11 이하의 `randomizesDwell`은 레거시 입력으로 계속 허용하되 서버가 공개 원본을 다시 쓰거나 임의 승격하지 마세요.
- 지원하는 v12는 정상 제작자 설정으로 처리하고 v13 이상은 미래 제작자 설정으로 분류하세요. D-121부터 일반 사용자가 불완전한 펫을 받지 않도록 제작자 설정 파일이 있으나 미래·손상 상태인 버전은 공개 승인하지 않습니다. 원본은 quarantine에 보존하고 제작자에게 지원 앱에서 다시 내보내도록 안내하세요. 제작자 설정 파일이 아예 없는 레거시 패키지는 별도 호환 상태로 공개할 수 있습니다.
- `createdWithMonglePetVersion`은 제작 정보일 뿐 게시·설치 차단 기준이 아닙니다. `minimumMonglePetVersion`은 package와 제작자 설정을 완전히 적용하는 데 필요한 버전이어야 하며, 현재 schema-v12 제작자 설정을 포함하면 최소 `1.7.0`인지 검사하세요. metadata의 최소 버전은 package manifest보다 낮을 수 없게 하고 불일치는 승인 전에 반려하세요.
- 관리자 승인 전에는 검색·상세·다운로드 API에 노출하지 마세요.
- 다운로드 시 SHA-256, 파일 크기, package version과 최소 MonglePet 앱 버전을 제공하세요.

## API 초안

- `GET /api/v1/pets`
- `GET /api/v1/pets/{slug}`
- `GET /api/v1/pets/{slug}/versions`
- `GET /api/v1/pet-versions/{id}/download`
- `POST /api/v1/uploads`
- `POST /api/v1/uploads/{id}/complete`
- `POST /api/v1/pets/{id}/versions`
- `PATCH /api/v1/pets/{id}`
- 댓글·좋아요·신고·관리자 검토 API

## 데스크톱 앱으로 열기

- 공개 펫 상세 화면에 `MonglePet에서 열기`를 추가하고 기존 `최신 버전 다운로드`와 역할을 분리하세요.
- 앱 링크는 API URL, 버전 UUID나 만료 다운로드 URL이 아니라 현재 환경에서 다시 조합한 canonical 공개 상세 URL을 전달합니다.
- 개발은 `https://dev.mapleroom.kr/monglepet/pets/{slug}`, 운영은 `https://mapleroom.kr/monglepet/pets/{slug}`를 사용합니다.
- 정확한 형식은 `monglepet://install?url={encodeURIComponent(canonicalDetailUrl)}`이며 query에는 `url` 하나만 둡니다.
- 사용자 클릭으로만 앱 링크를 열고, 1~1.5초 뒤에도 페이지가 visible이면 성공·실패를 단정하지 않는 `앱을 열지 못했나요?` 안내를 표시하세요.
- fallback은 `다시 시도`, `MonglePet 앱 다운로드`, `최신 버전 직접 다운로드`를 제공하되 자동 이동이나 자동 파일 다운로드를 시작하지 않습니다.
- 모바일과 지원하지 않는 OS에는 앱 열기 대신 데스크톱 앱 안내를 표시합니다.
- URL 조합 함수, 개발·운영 host, percent encoding, 잘못된 slug와 fallback 상태를 자동 테스트하세요.

## 작업 방식과 결과물

1. 기존 개인 API 서버, 언어·프레임워크, DB, object storage, reverse proxy, TLS와 인증 방식을 먼저 조사하세요.
2. 조사 결과를 바탕으로 아키텍처, 위협 모델, DB migration, OpenAPI와 단계별 작업 계획을 작성하세요.
3. 웹 요구 때문에 `.monglepet` 계약을 독자적으로 확장하지 말고 변경이 필요하면 MonglePet 저장소에서 먼저 결정하세요.
4. 정상·레거시 `license` 포함·`license` 미포함·손상·악성 fixture와 제작자 설정 v11·v12·미래 v13 fixture를 자동 테스트하세요.
5. 운영 서버에서 직접 개발하지 말고 검증된 artifact와 migration으로 배포하세요.
6. 구현 완료 시 contract commit, schema version, 배포·롤백 절차와 남은 위험을 문서화하세요.

먼저 구현하지 말고 현재 서버 환경 조사 결과, 제안 아키텍처, 데이터 모델과 단계별 계획을 검토용으로 제시해 주세요.

---
