---
description: Codex CLI(GPT)로 이미지 생성 — 프롬프트를 주면 프로젝트에 PNG로 저장
argument-hint: <만들 이미지 설명> [참고 이미지 경로]
allowed-tools: Bash(bash:*), Read
---

사용자 요청: $ARGUMENTS

Codex CLI의 이미지 생성 기능으로 위 요청의 이미지를 만든다.

1. 요청을 영어 이미지 프롬프트로 다듬는다(주제, 스타일, 배경, 구도). 사용자가 쓴 의도는 바꾸지 않는다.
2. 저장 경로를 정한다. 사용자가 경로를 말했으면 그대로 쓰고, 아니면 프로젝트 구조에 맞게 고른다
   (Unity 프로젝트면 `Assets/Art/Generated/<짧은-영문-이름>.png`, 그 외에는 `generated-images/<이름>.png`).
   같은 이름 파일이 있으면 덮어쓰지 말고 뒤에 `-2`, `-3`을 붙인다.
3. Bash 도구로 실행한다(1~3분 걸리므로 timeout 400000). 요청에 참고 이미지 경로가 있으면 `-i <경로>`를 추가한다.
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-image.sh" -o "<저장 경로>" "<프롬프트>"`
4. 성공하면 Read 도구로 이미지를 열어 요청과 맞는지 확인하고, 저장 경로와 함께 짧게 보고한다.
   실패하면 오류 내용을 그대로 전한다.
