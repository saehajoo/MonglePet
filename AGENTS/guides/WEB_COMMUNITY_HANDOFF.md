# MonglePet 웹 커뮤니티 인계 지침

## 1. 문서 목적

이 문서는 MonglePet 데스크톱 앱과 분리된 웹 커뮤니티 저장소를 만들 때 전달하는 초기 개발 지침이다.

웹 커뮤니티의 목표는 사용자가 `.monglepet` 펫을 검색하고 미리 본 뒤 내려받을 수 있게 하고, 인증된 제작자가 펫을 게시하며 로그인 사용자가 댓글·좋아요·신고에 참여할 수 있게 하는 것이다.

이 문서를 서버의 운영 디렉터리에서 바로 구현하라는 의미로 사용하지 않는다. 별도 Git 저장소와 개발·검증 환경에서 구현하고 배포 자동화로 개인 서버에 반영한다.

## 2. 저장소와 소유권 경계

### MonglePet 데스크톱 저장소

다음 항목의 단일 원본이다.

- `.monglepet` 패키지와 `pet.json` 형식
- `recommended-profile.json` 형식
- 패키지 보안 상한과 유효성 규칙
- 최소 호환 MonglePet 앱 버전의 의미
- 정상·오류·악성 패키지 fixture
- macOS와 Windows 앱의 설치 결과

웹 요구사항 때문에 이 저장소의 패키지 규격을 서버에서 독자적으로 확장하지 않는다. 공통 규격 변경이 필요하면 MonglePet 저장소에서 먼저 결정하고 버전·fixture를 갱신한다.

### 웹 커뮤니티 저장소

예시 이름은 `monglepet-community`이며 다음 책임을 가진다.

- 공개 웹 UI와 검색·상세·미리보기·다운로드
- 인증, 사용자 프로필과 제작자 표시
- 펫 업로드·버전 관리·게시 심사
- 댓글·좋아요·신고와 관리자 도구
- 데이터베이스 migration
- 원본 패키지와 파생 미리보기 저장
- 업로드 검사 worker
- 웹 API, 서버 배포와 운영 보안

데스크톱 앱 소스, Swift·AppKit 코드와 Windows UI 코드를 웹 저장소로 복사하지 않는다.

## 3. 새 저장소로 전달하는 방법

1. 개인 서버와 분리된 개발 환경에서 `monglepet-community` 저장소를 만든다.
2. 이 문서를 새 저장소의 초기 `AGENTS.md`로 복사하거나 최상위 `AGENTS.md`가 반드시 읽도록 연결한다.
3. 아래 파일을 버전이 명시된 계약 자료로 전달한다.
   - `AGENTS/specifications/PET_PACKAGE.md`
   - 정상 및 오류 `.monglepet` fixture
   - 향후 추가할 `pet.schema.json`
   - 향후 추가할 `recommended-profile.schema.json`
4. 계약 자료에는 원본 MonglePet 저장소의 Git commit과 schema 버전을 기록한다.
5. 서버 구현이 계약을 변경해야 한다면 웹 저장소에서만 고치지 말고 MonglePet 저장소에 변경 제안을 먼저 반영한다.

문서의 설명만 수동으로 다시 작성해 전달하지 않는다. JSON Schema와 fixture를 기계적으로 검증할 수 있는 계약으로 유지한다.

## 4. 구현 전 환경 조사

웹 코드를 만들기 전에 기존 개인 서버에서 다음을 확인하고 새 저장소의 결정 기록에 남긴다.

- 운영체제, CPU 아키텍처와 사용 가능한 메모리·디스크
- 기존 API 서버의 언어, 프레임워크와 지원 버전
- 기존 인증 방식과 OAuth/OIDC 공급자
- 데이터베이스 종류, 버전과 migration 도구
- S3 호환 object storage 또는 로컬 파일 저장 정책
- reverse proxy, TLS 인증서와 도메인 구성
- background worker와 작업 queue 사용 가능 여부
- CI/CD, staging 환경, 로그·모니터링과 백업 방식
- 이메일 발송이나 신고 알림 수단

기존 서버 스택이 유지보수·보안 요구를 충족하면 우선 재사용한다. 환경 조사 없이 새 언어, 프레임워크, 데이터베이스 또는 인증 체계를 추가하지 않는다.

운영 서버에서 소스 파일을 직접 수정하거나 운영 DB에 수동으로 schema를 적용하지 않는다.

## 5. 제품 범위

### 첫 공개 범위

- 비회원 펫 목록·검색·정렬·태그 필터
- 비회원 펫 상세 페이지와 정적 또는 애니메이션 미리보기
- 비회원 `.monglepet` 다운로드
- 로그인 사용자 펫 업로드와 자신의 게시물 수정·새 버전 추가·게시 중단
- 로그인 사용자 댓글 작성·수정·삭제
- 로그인 사용자 좋아요와 신고
- 관리자 게시 승인·반려·숨김과 신고 처리
- 이름, 제작자, 버전과 앱 호환 버전 표시
- 패키지 SHA-256과 파일 크기 표시
- 이용약관, 개인정보 안내, 저작권·삭제 요청 경로

### 후속 범위

- MonglePet 앱 안의 온라인 카탈로그
- URL 또는 custom scheme 기반 설치
- 데스크톱 앱에서 사용자 로그인·업로드
- 제작자 팔로우와 알림
- 다국어 UI
- 추천·인기 알고리즘 고도화

### 초기 제외 범위

- AI 펫 생성
- 유료 판매, 결제와 정산
- 실시간 채팅
- 비공개 펫 공유
- 원격 코드·스크립트·플러그인 배포
- 웹에서 사용자의 로컬 MonglePet 설정 변경

## 6. 접근 권한 정책

| 기능 | 비회원 | 로그인 사용자 | 작성자 | 관리자 |
| --- | --- | --- | --- | --- |
| 목록·검색·상세·미리보기 | 허용 | 허용 | 허용 | 허용 |
| 공개 펫 다운로드 | 허용 | 허용 | 허용 | 허용 |
| 펫 업로드 | 금지 | 허용 | 허용 | 허용 |
| 자신의 펫 수정·새 버전 | 금지 | 금지 | 허용 | 허용 |
| 댓글·좋아요·신고 | 금지 | 허용 | 허용 | 허용 |
| 게시 승인·반려·숨김 | 금지 | 금지 | 금지 | 허용 |
| 사용자 제재·신고 처리 | 금지 | 금지 | 금지 | 허용 |

첫 버전에서는 직접 비밀번호 인증을 새로 구현하지 않는다. 기존 개인 API 서버에 검증된 인증이 있으면 재사용하고, 없다면 OAuth/OIDC를 우선 검토한다.

인증과 작성자 권한은 서버에서 매 요청 다시 확인한다. UI에서 버튼을 숨기는 것만으로 권한을 제어하지 않는다.

## 7. 권장 서비스 구조

```text
Browser
  ├── Public Web
  └── Authenticated Web
          │
          ▼
API Service
  ├── Auth / Authorization
  ├── Catalog / Search
  ├── Pet / Version
  ├── Comment / Like / Report
  └── Admin Moderation
       │        │
       │        ├── Relational Database
       │        └── Object Storage
       │
       └── Upload Queue
                │
                ▼
        Package Validation Worker
          ├── ZIP 사전 검사
          ├── Manifest·이미지 검증
          ├── 미리보기 파생물 생성
          └── 검토 대기 상태 전환
```

작은 초기 서비스에서는 API와 worker를 같은 코드베이스에 둘 수 있지만 실행 책임과 권한은 분리한다. 업로드 검사처럼 CPU·메모리를 많이 쓰는 작업을 웹 요청 프로세스에서 장시간 동기 실행하지 않는다.

## 8. 핵심 데이터 모델

### User

- 서버 내부 UUID
- 인증 공급자의 안정적인 subject
- 공개 표시 이름과 선택적 프로필 이미지
- 역할: `user`, `moderator`, `admin`
- 상태: `active`, `suspended`, `deleted`
- 생성·수정 시각

이메일과 인증 토큰은 공개 API에 노출하지 않는다.

### Pet

- 서버 내부 UUID
- 공개 slug
- `.monglepet`의 안정적인 package ID
- 소유 사용자 ID
- 공개 이름, 설명과 태그
- 대표 버전 ID
- 상태: `draft`, `processing`, `pendingReview`, `published`, `rejected`, `hidden`, `deleted`
- 생성·수정·게시 시각

package ID는 제작자가 정한 식별자이고 서버 Pet UUID와 동일하지 않다.

### PetVersion

- 서버 내부 UUID와 Pet ID
- 패키지 버전
- `formatVersion`
- `createdWithMonglePetVersion`
- `minimumMonglePetVersion`
- 제작자 snapshot
- 원본 object key
- SHA-256, 압축 크기와 압축 해제 크기
- 공개 미리보기 metadata
- 검증기 버전과 검증 시각
- 게시 상태와 생성 시각

게시된 버전의 원본 패키지와 SHA-256은 변경하지 않는다. 수정된 파일은 같은 버전을 덮어쓰지 않고 새 PetVersion으로 등록한다.

### Community

- `Comment`: Pet ID, 작성자, 본문, 상태, 생성·수정 시각
- `Like`: Pet ID와 사용자 ID의 유일 조합
- `Report`: 대상 종류·ID, 신고자, 사유, 처리 상태와 관리자 기록
- `Tag`: 정규화된 이름과 slug

다운로드 횟수는 개인별 다운로드 이력을 장기 보관하지 않고 집계 중심으로 기록한다.

## 9. 공개 API 초안

API는 처음부터 `/api/v1`처럼 버전을 지정한다. 실제 필드와 오류 형식은 OpenAPI 문서로 확정한다.

### 비회원 허용

- `GET /api/v1/pets`
- `GET /api/v1/pets/{slug}`
- `GET /api/v1/pets/{slug}/versions`
- `GET /api/v1/pet-versions/{id}/download`
- `GET /api/v1/pets/{slug}/comments`
- `GET /api/v1/tags`

목록 API는 cursor pagination을 사용하고 검색·태그·정렬 조건에 상한을 둔다.

### 로그인 필요

- `GET /api/v1/me`
- `POST /api/v1/uploads`
- `POST /api/v1/uploads/{id}/complete`
- `POST /api/v1/pets/{id}/versions`
- `PATCH /api/v1/pets/{id}`
- `POST /api/v1/pets/{id}/comments`
- `PATCH /api/v1/comments/{id}`
- `DELETE /api/v1/comments/{id}`
- `PUT /api/v1/pets/{id}/like`
- `DELETE /api/v1/pets/{id}/like`
- `POST /api/v1/reports`

### 관리자

- `GET /api/v1/admin/review-queue`
- `POST /api/v1/admin/pet-versions/{id}/approve`
- `POST /api/v1/admin/pet-versions/{id}/reject`
- `POST /api/v1/admin/pets/{id}/hide`
- `POST /api/v1/admin/reports/{id}/resolve`

서버 내부 object key, 파일 시스템 경로, 사용자 이메일과 인증 공급자 token은 API 응답에 포함하지 않는다.

## 10. `.monglepet` 업로드 처리

업로드된 파일과 브라우저가 보낸 manifest 요약은 모두 신뢰하지 않는다. 서버가 원본 패키지를 독립적으로 검사해 metadata를 다시 만든다.

처리 순서는 다음과 같다.

1. 인증·계정 상태·업로드 rate limit을 확인한다.
2. 파일을 공개되지 않는 quarantine object 또는 임시 공간에 저장한다.
3. 전송 중 크기 상한을 적용하고 SHA-256을 계산한다.
4. ZIP 전체를 해제하기 전에 엔트리 metadata를 순회한다.
5. 경로 탈출, 절대 경로, 심볼릭 링크, 중복·충돌 경로와 비정상 압축률을 거부한다.
6. 허용된 JSON·PNG·정적 WebP 이외의 파일과 실행 코드·스크립트를 거부한다.
7. 격리된 임시 디렉터리에 허용 엔트리만 개별 해제한다.
8. `pet.json`, 선택적 `recommended-profile.json`, 이미지 형식·픽셀·알파·프레임 영역과 시간을 검증한다.
9. 로그인한 업로더의 게시 권한 확인 상태를 검사한다. 레거시 `license` 문자열은 저장하거나 판별하지 않는다.
10. 웹 공개용 정적·애니메이션 미리보기 파생물을 만든다.
11. 검증 결과를 `pendingReview`로 저장하고 관리자 승인 전에는 공개 목록과 다운로드에 노출하지 않는다.
12. 승인 시 DB metadata와 immutable 원본 object를 하나의 게시 작업으로 연결한다.
13. 실패·반려·시간 초과 upload의 임시 파일을 보존 정책에 따라 제거한다.

MonglePet 패키지 규격의 현재 초기 상한을 최소 기준으로 적용한다.

- 압축 크기: 20 MiB
- 압축 해제 크기: 100 MiB
- 전체 디코딩 픽셀 예산: 64 MiPixels
- ZIP 엔트리 수: 2,000
- 엔트리별·전체 압축률: 100:1
- 단일 이미지 한 변: 8192 px
- 전체 프레임 수: 1,000
- 모션 수: 100
- `recommended-profile.json`: 1 MiB

웹 운영 보호를 위해 더 낮은 업로드 상한을 둘 수는 있지만 앱 규격보다 큰 파일을 허용하거나 앱이 거부하는 패키지를 정상으로 게시해서는 안 된다.

검증 실패는 외부 사용자에게 안전한 오류 코드와 필드 수준 설명만 제공한다. 서버 경로, stack trace와 내부 object key를 노출하지 않는다.

## 11. 콘텐츠 권리와 운영 정책

웹 업로드는 데스크톱 앱의 로컬 내보내기보다 공개 배포 위험이 크므로 다음을 모두 요구한다.

- 업로더가 자산을 게시할 권한이 있음을 명시적으로 확인
- 표시할 제작자 확인
- 서비스 이용약관과 게시 정책 동의
- 신고와 삭제 요청 경로 제공
- 관리자의 게시 전 검토

`.monglepet`의 레거시 `license` 필드는 공개 metadata, 검색 필터와 게시 허용 판정에 사용하지 않는다. 필드가 없거나 어떤 문자열이 들어 있어도 패키지 구조가 유효하면 같은 방식으로 처리한다. 대신 로그인한 업로더가 이미지 자산을 게시할 권한이 있음을 업로드마다 확인하고 관리자 검토, 신고, 임시 숨김과 삭제 요청 절차를 운영한다.

유명 캐릭터·브랜드·실존 인물을 사용한 펫은 단순 면책 문구만으로 안전하다고 판단하지 않는다. 신고 접수, 임시 숨김, 삭제와 반복 위반자 제재 절차를 운영 정책에 포함한다.

법률 자문이 필요한 항목을 코드 규칙만으로 확정하지 않는다.

## 12. 웹 미리보기

웹페이지가 원본 `.monglepet` ZIP을 브라우저에서 직접 해제해 신뢰하는 방식을 기본으로 사용하지 않는다.

서버 검증이 끝난 뒤 다음 파생물을 공개한다.

- 정적 대표 이미지
- 허용된 atlas 이미지 또는 미리보기 전용 이미지
- 프레임 좌표·지연 시간·반복 여부만 포함하는 정규화된 preview JSON
- 이미지 크기, 모션 목록과 전체 재생 시간

첫 공개 버전은 정적 미리보기만 제공해도 된다. 애니메이션 미리보기는 검증된 파생 atlas와 preview JSON을 Canvas 또는 일반 이미지 요소로 재생한다.

화질 보존이 중요하면 원본 atlas 픽셀을 불필요하게 확대·재인코딩하지 않는다. 목록 썸네일만 별도 크기로 생성하고 상세 미리보기는 검증된 원본 비율을 유지한다.

SVG, HTML 또는 사용자 제공 스크립트를 미리보기 자산으로 허용하지 않는다.

## 13. 다운로드

- 공개 승인된 PetVersion만 비회원에게 다운로드를 허용한다.
- 다운로드 파일은 검증·승인된 immutable 원본 `.monglepet`이다.
- 응답은 안전한 `Content-Disposition: attachment` 파일명을 사용한다.
- SHA-256, 파일 크기, 패키지 버전과 최소 앱 버전을 상세 페이지와 API에 표시한다.
- object storage의 공개 URL 또는 짧은 수명의 signed URL을 사용할 수 있지만 내부 object key는 API 계약으로 취급하지 않는다.
- 다운로드 집계는 요청 실패·봇·중복 요청 정책을 정하고 비동기적으로 처리한다.
- 악용 방지를 위한 IP 기반 rate limit은 원본 IP의 장기 분석 저장과 분리한다.

향후 MonglePet 앱이 URL 설치를 지원하면 다운로드 전에 SHA-256과 최소 앱 버전을 확인하고, 앱 설치 과정에서도 기존 로컬 패키지 검증을 다시 실행한다. 웹 검증 결과만 신뢰해 앱 검증을 생략하지 않는다.

## 14. 댓글·좋아요·신고

- 댓글 본문은 일반 텍스트로 시작하고 HTML 입력을 허용하지 않는다.
- 길이, 작성 빈도와 페이지당 개수에 상한을 둔다.
- 출력 시 항상 escape하고 저장·수정·삭제 권한을 서버에서 확인한다.
- 삭제 댓글은 감사와 분쟁 처리에 필요한 최소 기간만 보존하고 공개 응답에서는 제거한다.
- 좋아요는 사용자와 Pet의 유일 조합으로 중복을 방지한다.
- 신고는 대상 snapshot, 사유, 처리 상태와 최소한의 관리자 기록을 남긴다.
- 정지 계정은 새 업로드·댓글·좋아요·신고를 만들 수 없다.

cookie 기반 session을 사용하면 CSRF 방어, `Secure`, `HttpOnly`, 적절한 `SameSite` 정책을 적용한다. 모든 인증 경로는 TLS만 허용한다.

## 15. 개인정보와 보안

- 공개 활동에 필요하지 않은 개인정보를 수집하지 않는다.
- 비회원 다운로드를 위해 회원가입을 강제하지 않는다.
- 실제 비밀번호를 직접 저장하지 않는 인증 방식을 우선한다.
- access token, session, object storage credential과 DB 비밀번호를 Git에 저장하지 않는다.
- 운영·staging·개발 환경의 credential과 DB를 분리한다.
- 업로드 파일명, 댓글, 표시 이름과 검색어를 로그에 무제한 기록하지 않는다.
- 관리자 작업은 감사 로그를 남긴다.
- API별 rate limit, request body 상한과 timeout을 설정한다.
- 보안 헤더, CSP, CORS와 cookie 정책은 실제 배포 도메인을 기준으로 제한한다.
- DB와 object storage의 백업·복원 절차를 정기적으로 검증한다.

## 16. 배포 원칙

- 최소 `development`, `staging`, `production` 환경을 분리한다.
- Git commit과 재현 가능한 빌드 산출물로 배포한다.
- production 서버에서 `git pull` 후 수동 수정하는 방식을 배포 절차로 사용하지 않는다.
- DB migration은 버전 관리하고 배포 전후 호환 순서를 문서화한다.
- 새 package validator는 기존 공개 패키지 fixture에 대한 회귀 테스트를 통과한 뒤 배포한다.
- object storage 정리 작업은 DB 게시 상태와 보존 기간을 확인하며 즉시 영구 삭제하지 않는다.
- health check, 오류율, queue 적체, 저장 공간과 백업 실패를 모니터링한다.

개인 서버 한 대에서 시작하더라도 API, DB, object storage와 worker의 데이터 경계 및 백업 책임은 문서로 분리한다.

## 17. 테스트 계약

### 패키지 검증

- MonglePet 앱이 허용하는 정상 fixture를 웹 validator도 허용
- 경로 탈출, 절대 경로와 심볼릭 링크 거부
- 중복 경로, 대소문자 충돌과 ZIP bomb 거부
- 실행 파일·스크립트·animated WebP 거부
- 잘못된 manifest, 이미지 범위, 프레임 시간과 호환 버전 거부
- SHA-256과 저장된 원본의 일치
- 검증 실패와 관리자 반려 시 공개 object가 남지 않음

### API와 권한

- 비회원 목록·상세·다운로드 허용
- 비회원 업로드·댓글·좋아요·신고 거부
- 다른 사용자의 펫·댓글 수정 거부
- 관리자 endpoint의 역할 확인
- pagination, 검색과 rate limit 경계
- 삭제·숨김 펫 다운로드 차단

### 웹 보안

- 댓글과 표시 이름의 XSS escape
- CSRF와 session cookie 정책
- 업로드 content type 위조
- 과대 request와 느린 upload timeout
- 내부 경로·credential·stack trace 비노출

### 운영

- DB migration 전진·롤백 또는 복구 절차
- DB와 object storage 백업 복원
- worker 재시도 idempotency
- 동일 package version과 SHA-256 중복 업로드 정책
- staging에서 게시·숨김·삭제 전체 흐름

## 18. 단계별 구현 순서

### Phase W0: 계약 고정

- MonglePet Swift validator와 `PET_PACKAGE.md`의 차이 확인
- `pet.schema.json`, `recommended-profile.schema.json`과 공통 fixture 생성
- 웹 metadata DTO와 OpenAPI 초안
- 게시 권한 확인·신고·삭제 정책 초안

### Phase W1: 읽기 전용 카탈로그

- 관리자가 검증된 패키지를 등록하는 내부 절차
- 공개 목록·검색·상세·정적 미리보기
- 익명 다운로드, SHA-256과 호환 버전 표시
- DB·object storage 백업 기준선

### Phase W2: 인증·업로드·검토

- 인증과 사용자 프로필
- quarantine upload와 validation worker
- 작성자 관리 화면
- 관리자 승인·반려·숨김
- 애니메이션 미리보기

### Phase W3: 커뮤니티

- 댓글·좋아요·신고
- 사용자 제재와 관리자 감사 로그
- 이용약관, 개인정보 안내와 저작권 삭제 요청

### Phase W4: 앱 연동

- 데스크톱 앱용 읽기 전용 catalog API
- 다운로드 SHA-256과 최소 버전 사전 확인
- URL 설치 또는 앱으로 열기
- macOS·Windows 교차 설치 QA

각 Phase는 독립 배포와 롤백이 가능해야 한다. W1 검증 전 W2 업로드를 공개하지 않는다.

## 19. 웹 저장소에서 먼저 결정할 열린 항목

- 기존 개인 API 서버의 재사용 범위
- frontend, API와 worker 기술 스택
- 데이터베이스와 object storage
- 인증 공급자와 공개 프로필 범위
- 게시 권한 확인 문구와 수동 검토 정책
- 관리자 수와 비상 복구 방식
- 검색 방식과 태그 관리
- 다운로드 집계·rate limit 정책
- 댓글 보존과 계정 삭제 정책
- 도메인, 서비스 명칭과 브랜딩

이 항목을 추측해 production 구조를 만들지 않는다. 환경 조사 결과와 사용자의 결정을 새 웹 저장소의 `DECISIONS.md`에 기록한다.

## 20. 첫 인계 완료 조건

- 별도 웹 저장소와 개발 환경이 준비됨
- 이 문서가 새 저장소의 최상위 작업 지침에서 연결됨
- MonglePet contract commit과 schema 버전이 기록됨
- 기존 서버 환경 조사와 기술 결정이 문서화됨
- W0 작업 계획과 보안 위협 목록이 작성됨
- 정상·오류·악성 fixture로 validator 테스트가 실행됨
- staging에서 목록·상세·미리보기·익명 다운로드가 동작함
- production 배포 전 백업 복원이 실제로 검증됨

---

문서 상태: draft
작성일: 2026-07-31
원본 저장소: MonglePet
