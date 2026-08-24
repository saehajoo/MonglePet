# 플랫폼 공통 내장 펫

`Mongle.monglepet/`은 macOS `1.3.0 (5)`에서 확정한 내장 몽글이의 데이터 전용 기준본이다. Windows는 `apps/macos`의 asset catalog를 직접 참조하지 않고 이 디렉터리를 앱 출력과 publish에 포함한다.

- 예약 ID: `kr.mapleroom.monglepet.builtin.mongle`
- 콘텐츠 버전: `1.0.1`
- 제작자: `운영자`
- 10개 모션, 36프레임, 150×150px 셀
- 원본 외부 패키지 SHA-256: `00503aab356602e0af8339201c653af05cd24aea8db7dca561e6508d519e8617`

`recommended-profile.json`은 운영체제에 독립적인 행동·입력 없음·이동·쓰다듬기·말풍선 값만 포함한다. Codex 전면 앱 규칙은 macOS의 `com.openai.codex`와 Windows의 `pfn:`/`exe:` 식별자가 다르므로 각 플랫폼 built-in 기본값 코드에서 추가하고 공통 JSON에는 넣지 않는다.

외부 웹 패키지의 사용자 ID와 설명은 내장 예약 메타데이터로 바꿨고, 앱 호환성 기록은 이 기준본이 확정된 `1.3.0`으로 갱신했다. 이미지 픽셀과 모션·프레임 값은 기준 패키지에서 변경하지 않는다.
