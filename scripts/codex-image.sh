#!/usr/bin/env bash
# Codex CLI의 이미지 생성 기능으로 이미지를 만들어 지정한 경로에 저장한다.
# Codex 로그인(codex login)만 있으면 되고 OPENAI_API_KEY는 필요 없다.
#
# 사용: codex-image.sh -o <저장 경로.png> [-i <참고 이미지>]... <프롬프트>
#   -o  저장할 파일 경로 (폴더가 없으면 만든다)
#   -i  참고/편집할 이미지 (여러 번 지정 가능)
# 성공하면 저장한 파일 경로를 stdout에 출력한다.

out_path=""
refs=()
while getopts "o:i:" opt; do
  case "$opt" in
    o) out_path="$OPTARG" ;;
    i) refs+=(-i "$OPTARG") ;;
    *) echo "사용: $0 -o <저장 경로.png> [-i <참고 이미지>]... <프롬프트>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
prompt="$*"

if [ -z "$out_path" ] || [ -z "$prompt" ]; then
  echo "사용: $0 -o <저장 경로.png> [-i <참고 이미지>]... <프롬프트>" >&2
  exit 1
fi
command -v codex >/dev/null 2>&1 || { echo "codex CLI가 없습니다 (npm i -g @openai/codex 후 codex login)" >&2; exit 1; }

gen_dir="$HOME/.codex/generated_images"
mkdir -p "$gen_dir"
marker=$(mktemp)
log=$(mktemp)
trap 'rm -f "$marker" "$log"' EXIT

# 이미지 생성은 Codex 내장 도구라 셸 권한이 필요 없다. read-only로 돌리고 파일은 직접 가져온다.
model_args=()
[ -n "$CODEX_IMAGE_MODEL" ] && model_args=(-m "$CODEX_IMAGE_MODEL")
codex exec "${model_args[@]}" "${refs[@]}" --sandbox read-only --skip-git-repo-check --ephemeral --color never - \
  > "$log" 2>&1 <<EOF
이미지 생성 도구로 아래 요청대로 이미지를 정확히 한 장 만들어라. 파일 저장이나 셸 명령은 하지 않는다.
첨부 이미지가 있으면 그것을 참고하거나 편집 대상으로 삼는다.

요청: $prompt
EOF

# 이번 실행에서 새로 생긴 이미지 중 가장 최근 것
img=$(find "$gen_dir" -type f -newer "$marker" \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) -print0 2>/dev/null |
  xargs -0 ls -t 2>/dev/null | head -1)

if [ -z "$img" ]; then
  echo "이미지 생성 실패. Codex 출력:" >&2
  grep -E 'ERROR|error' "$log" | tail -5 >&2
  tail -5 "$log" >&2
  exit 1
fi

mkdir -p "$(dirname "$out_path")"
cp "$img" "$out_path" && echo "$out_path"
