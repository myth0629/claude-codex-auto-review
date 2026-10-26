#!/usr/bin/env bash
# Claude Code Stop 훅: Claude가 응답을 마칠 때 커밋되지 않은 변경을 Codex가 리뷰한다.
# 문제가 있으면 exit 2 + stderr로 리뷰 내용을 Claude에게 돌려보내 수정하게 한다.
#
# 끄기: /codex-auto-review:toggle off (전역, ~/.claude/codex-auto-review/off 파일),
#       프로젝트에 .claude/no-codex-review 파일, 또는 환경변수 CODEX_REVIEW=0

state_dir="$HOME/.claude/codex-auto-review"
mkdir -p "$state_dir"
off_flag="$state_dir/off"

# 토글: codex-review.sh toggle [on|off|status]  (/codex-auto-review:toggle 명령이 사용)
if [ "$1" = "toggle" ]; then
  case "${2:-status}" in
    on)  rm -f "$off_flag" ;;
    off) touch "$off_flag" ;;
  esac
  [ -f "$off_flag" ] && echo "Codex 자동 리뷰: OFF" || echo "Codex 자동 리뷰: ON"
  exit 0
fi

input=$(cat)

[ "${CODEX_REVIEW:-1}" = "0" ] && exit 0
[ -f "$off_flag" ] && exit 0

# 훅 때문에 Claude가 이어서 작업한 턴이면 다시 리뷰하지 않음 (무한 루프 방지)
echo "$input" | grep -q '"stop_hook_active" *: *true' && exit 0

# git 저장소가 아니면 통과
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
cd "$(git rev-parse --show-toplevel)" || exit 0

[ -f .claude/no-codex-review ] && exit 0
command -v codex >/dev/null 2>&1 || exit 0

# 리뷰 노이즈가 되는 파일 제외 (Unity 직렬화 파일, lock 파일 등)
EXCLUDES=(
  ':(exclude,glob)**/*.meta' ':(exclude,glob)**/*.unity' ':(exclude,glob)**/*.prefab'
  ':(exclude,glob)**/*.asset' ':(exclude,glob)**/*.mat' ':(exclude,glob)**/*.anim'
  ':(exclude,glob)**/*.controller' ':(exclude,glob)**/*.lock'
  ':(exclude,glob)**/package-lock.json' ':(exclude,glob)**/packages-lock.json'
)

# 변경 상태 지문: 마지막 리뷰 이후 바뀐 게 없으면 다시 리뷰하지 않음
status=$(git status --porcelain -uall -- . "${EXCLUDES[@]}")
[ -z "$status" ] && exit 0
state="$status$(git diff HEAD -- . "${EXCLUDES[@]}" 2>/dev/null)"

stamp_file="$(git rev-parse --git-dir)/codex-review-last"
hash=$(printf '%s' "$state" | git hash-object --stdin)
[ -f "$stamp_file" ] && [ "$(cat "$stamp_file")" = "$hash" ] && exit 0
echo "$hash" > "$stamp_file"

out=$(mktemp)
err=$(mktemp)
trap 'rm -f "$out" "$err"' EXIT
log="$state_dir/review.log"

# 모든 리뷰 결과를 log에 기록: write_log <결과> <본문>
write_log() {
  {
    echo "===== [$(date '+%F %T')] $(basename "$(pwd)") | $1 | ${SECONDS}초"
    echo "$(pwd)"
    [ -n "$2" ] && echo "$2"
    echo
  } >> "$log"
}

# 변경 내용을 프롬프트에 직접 넣는다. read-only 샌드박스(특히 Windows)에서는 Codex가
# 셸/파일 조회에 실패해 리뷰를 못 하는 경우가 있어, 파일을 직접 읽지 않아도 되게 한다.
prompt=$(mktemp)
trap 'rm -f "$out" "$err" "$prompt"' EXIT
max_bytes="${CODEX_REVIEW_MAX_BYTES:-400000}"
{
  echo "아래는 이 git 저장소의 커밋되지 않은 변경이다(git diff HEAD + 새로 추가된 파일)."
  echo "직렬화 파일(.meta/.unity/.prefab/.asset 등)과 lock 파일은 이미 제외했다."
  echo "이 diff만 보고 코드 리뷰해라. 주변 코드가 꼭 필요할 때만 파일을 열어 보고, 열지 못하면 diff만으로 판단한다."
  echo "실제 버그, 크래시, 로직 오류, 보안 문제만 지적한다. 스타일 취향은 지적하지 않는다."
  echo "각 항목은 '- 파일:줄 — 문제 — 근거' 형식으로 쓴다."
  echo "지적할 문제가 없으면 다른 말 없이 정확히 LGTM 한 단어만 출력한다."
  echo
  echo '```diff'
  {
    git diff HEAD -U12 -- . "${EXCLUDES[@]}" 2>/dev/null
    git ls-files --others --exclude-standard -z -- . "${EXCLUDES[@]}" |
      while IFS= read -r -d '' f; do
        git diff --no-index -- /dev/null "$f" 2>/dev/null
      done
  } | head -c "$max_bytes"
  echo
  echo '```'
} > "$prompt"
[ "$(wc -c < "$prompt")" -ge "$max_bytes" ] && echo "(diff가 길어 ${max_bytes}바이트에서 잘렸다. 잘린 부분은 리뷰하지 않았다고 밝혀라.)" >> "$prompt"

# 모델/추론 강도 (CODEX_REVIEW_MODEL, CODEX_REVIEW_EFFORT로 변경 가능)
codex exec -m "${CODEX_REVIEW_MODEL:-gpt-6.1-sol}" -c model_reasoning_effort="${CODEX_REVIEW_EFFORT:-high}" \
  --sandbox read-only --ephemeral --color never -o "$out" - \
  > "$err" 2>&1 < "$prompt"

review=$(cat "$out" 2>/dev/null)

# Codex 실행 실패 시 작업을 막지 않되, 원인을 로그로 남김
if [ -z "$review" ]; then
  write_log "실패" "$(grep -E '^ERROR' "$err" | tail -3)"
  rm -f "$stamp_file"
  exit 0
fi

# 첫 줄이 LGTM이면 통과 (모델이 뒤에 설명을 덧붙이는 경우가 있음)
if echo "$review" | grep -m1 -v '^[[:space:]]*$' | tr -d '[:space:]*`' | grep -qx 'LGTM'; then
  write_log "LGTM" "$review"
  exit 0
fi

write_log "지적" "$review"
{
  echo "[Codex 리뷰] 커밋되지 않은 변경에 대해 Codex가 아래 문제를 지적했습니다."
  echo "각 항목을 코드로 확인해 타당한 것만 수정하고, 동의하지 않는 항목은 이유를 짧게 설명하세요."
  echo
  echo "작업을 마친 뒤 최종 답변 끝에 반드시 '## Codex 리뷰' 섹션을 넣어 사용자에게 보고하세요."
  echo "각 지적 사항마다 한 줄씩: 지적 내용(파일:줄) → 반영함 / 반영 안 함(이유)."
  echo
  echo "$review"
} >&2
exit 2
