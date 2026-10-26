# codex-auto-review

Claude Code가 응답을 마칠 때마다 커밋되지 않은 변경을 [OpenAI Codex CLI](https://github.com/openai/codex)가 자동으로 리뷰하는 플러그인입니다.
Codex가 문제를 지적하면 그 내용이 Claude에게 돌아가고, Claude가 타당한 항목을 수정한 뒤 답변 끝의 `## Codex 리뷰` 섹션에 결과를 보고합니다.

## 요구 사항

- [Codex CLI](https://github.com/openai/codex) 설치 및 로그인 (`codex login`)
- `bash`와 `git` (Windows는 Git for Windows의 Git Bash)

## 설치

Claude Code에서:

```
/plugin marketplace add myth0629/claude-codex-auto-review
/plugin install codex-auto-review@codex-auto-review
```

업데이트:

```
/plugin marketplace update codex-auto-review
```

## 사용

설치하면 바로 동작합니다. git 저장소에서 변경이 있을 때만 리뷰하고, 같은 diff는 다시 리뷰하지 않습니다.
Unity 직렬화 파일(`.meta`, `.unity`, `.prefab`, `.asset` 등)과 lock 파일은 리뷰 대상에서 제외합니다.

| 하고 싶은 것 | 방법 |
|---|---|
| 전역으로 끄기/켜기 | `/codex-auto-review:toggle off` / `on` |
| 상태 확인 | `/codex-auto-review:toggle` |
| 특정 프로젝트에서만 끄기 | 그 저장소에 `.claude/no-codex-review` 파일 생성 |
| 리뷰 기록 보기 | `~/.claude/codex-auto-review/review.log` |

## 설정 (환경 변수)

| 변수 | 기본값 | 설명 |
|---|---|---|
| `CODEX_REVIEW_MODEL` | `gpt-6.1-sol` | 리뷰에 쓸 Codex 모델 |
| `CODEX_REVIEW_EFFORT` | `high` | 추론 강도 (`low`/`medium`/`high`/`xhigh`) |
| `CODEX_REVIEW_MAX_BYTES` | `400000` | 프롬프트에 넣을 diff 최대 크기 |
| `CODEX_REVIEW` | `1` | `0`이면 비활성화 |

Codex 실행이 실패하면(모델 미지원, 로그인 만료 등) 작업을 막지 않고 `review.log`에 `실패`로 기록합니다.

## 동작 방식

1. Claude가 응답을 마치면 Stop 훅이 실행됩니다.
2. 변경 사항의 diff를 만들어 `codex exec --sandbox read-only`에 넘깁니다.
3. 첫 줄이 `LGTM`이면 통과하고, 아니면 exit 2로 리뷰 내용을 Claude에게 전달합니다.
4. 리뷰 반영으로 이어진 턴은 다시 리뷰하지 않습니다(무한 루프 방지).

## License

MIT
