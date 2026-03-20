#!/usr/bin/env bash
# 次の UC 仕様のひな形を作成する（Git ブランチの作成・切替は行わない）。
# 使用例:
#   ./uc-next-start.sh "task-management" "タスク管理機能追加" "タスク管理"
#   ./uc-next-start.sh UC-2 "order-cancel" "注文キャンセル" "注文"
#   ./uc-next-start.sh --yes "task-management" "タスク管理機能追加" "タスク管理"
# 引数仕様（位置引数）:
#   [UC-ID] [SLUG] [TITLE] [CATEGORY]
#   - UC-ID: 省略可（例: UC-2）
#   - SLUG: 必須。識別用の短名（ASCII, kebab-case 推奨。ファイル名には使わず参考・一貫性のため）
#   - TITLE: 必須。UC ファイル題名（日本語推奨）
#   - CATEGORY: 必須。docs/02_ユースケース仕様/ 配下のカテゴリ名（日本語可）
# 重要: 空欄の引数は禁止。SLUG/TITLE/CATEGORY は必ず指定する

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Error: Git リポジトリ内で実行してください。" >&2
  exit 1
}

YES_MODE=false
ARGS=()
for a in "$@"; do
  case "$a" in
    --yes|-y) YES_MODE=true ;;
    *)
      if [[ -z "$a" ]]; then
        echo "Error: 空文字の引数は使用できません。UC-ID を省略する場合は引数自体を渡さないでください。" >&2
        exit 1
      fi
      ARGS+=("$a")
      ;;
  esac
done

PROJECT_JSON="$REPO_ROOT/.spec-runner/project.json"
[[ -f "$PROJECT_JSON" ]] || { echo "uc-next-start: project.json がありません: $PROJECT_JSON" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "uc-next-start: jq が必要です（brew install jq）" >&2; exit 1; }
UC_ID_RE="$(jq -r '.naming.uc_id_pattern' "$PROJECT_JSON")"
[[ -n "$UC_ID_RE" && "$UC_ID_RE" != "null" ]] || {
  echo "uc-next-start: project.json の naming.uc_id_pattern が未設定です" >&2
  exit 1
}

next_uc_id() {
  local dir="$REPO_ROOT/docs/02_ユースケース仕様"
  mkdir -p "$dir"
  local max=0
  for f in "$dir"/*/UC-*.md; do
    [[ -e "$f" ]] || continue
    base=$(basename "$f" .md)
    if [[ "$base" =~ ^(${UC_ID_RE})- ]]; then
      uc_id="${BASH_REMATCH[1]}"
      digits=$(echo "$uc_id" | tr -cd '0-9')
      [[ -z "$digits" ]] && continue
      n=$((10#$digits))
      [[ $n -gt $max ]] && max=$n
    fi
  done
  printf "UC-%d\n" $((max + 1))
}

NEXT_UC="$(next_uc_id)"
SLUG=""
TITLE=""
CATEGORY=""
if [[ ${#ARGS[@]} -ge 1 ]] && [[ "${ARGS[0]}" =~ ^${UC_ID_RE}$ ]]; then
  [[ ${#ARGS[@]} -eq 4 ]] || {
    echo "Usage: .spec-runner/scripts/uc-next-start.sh [UC-ID] \"SLUG\" \"TITLE\" \"CATEGORY\" [--yes]" >&2
    echo "  - UC-ID を指定した場合は SLUG/TITLE/CATEGORY の3引数が必須です" >&2
    exit 1
  }
  NEXT_UC="${ARGS[0]}"
  SLUG="${ARGS[1]}"
  TITLE="${ARGS[2]}"
  CATEGORY="${ARGS[3]}"
else
  [[ ${#ARGS[@]} -eq 3 ]] || {
    echo "Usage: .spec-runner/scripts/uc-next-start.sh [UC-ID] \"SLUG\" \"TITLE\" \"CATEGORY\" [--yes]" >&2
    echo "  - UC-ID は任意、SLUG/TITLE/CATEGORY は必須です（空文字禁止）" >&2
    exit 1
  }
  SLUG="${ARGS[0]}"
  TITLE="${ARGS[1]}"
  CATEGORY="${ARGS[2]}"
fi

if [[ -z "$SLUG" || -z "$TITLE" || -z "$CATEGORY" ]]; then
  echo "Usage: .spec-runner/scripts/uc-next-start.sh [UC-ID] \"SLUG\" \"TITLE\" \"CATEGORY\" [--yes]" >&2
  echo "  - UC-ID は任意、SLUG/TITLE/CATEGORY は必須です（空文字禁止）" >&2
  exit 1
fi

SLUG=$(echo "$SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//' | sed 's/-*$//')
if [[ -z "$SLUG" ]]; then
  echo "Error: SLUG は英数字・ハイフンへ正規化可能な値を指定してください（例: task-management）。" >&2
  exit 1
fi

DOC_TITLE="$TITLE"
DOC_TITLE=$(echo "$DOC_TITLE" | sed 's/[\\\\\\/\\:\\*\\?\\\"\\<\\>\\|]/ /g' | sed 's/[[:space:]]\\+/ /g' | sed 's/^ *//; s/ *$//')
if [[ -z "$DOC_TITLE" ]]; then
  echo "Error: TITLE が不正です（危険文字除去後に空になりました）。" >&2
  exit 1
fi

CATEGORY=$(echo "$CATEGORY" | sed 's/[\\\/:\*\?"<>|]//g' | sed 's/[[:cntrl:]]//g' | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//; s/ *$//')
if [[ -z "$CATEGORY" ]]; then
  echo "Error: CATEGORY は空にできません。" >&2
  exit 1
fi

FEATURE_DIR="docs/02_ユースケース仕様/${CATEGORY}"
UC_DOC="${FEATURE_DIR}/${NEXT_UC}-${DOC_TITLE}.md"

if [[ -f "$UC_DOC" ]]; then
  echo "Error: 既に存在します: $UC_DOC" >&2
  exit 1
fi

UC_ID_PATTERN="^${UC_ID_RE}$"
if ! echo "$NEXT_UC" | grep -qE "$UC_ID_PATTERN"; then
  echo "Error: UC-ID が命名規則に合いません: $NEXT_UC（期待: $UC_ID_PATTERN）" >&2
  exit 1
fi

if [[ "$YES_MODE" != true ]]; then
  echo "次の UC 仕様のひな形を作成します（ブランチは作成しません）。"
  echo "  → $UC_DOC"
  echo -n "  実行してよろしいですか？ [y/N]: "
  read -r ans
  case "$ans" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "キャンセルしました。"; exit 0 ;;
  esac
fi

mkdir -p "$FEATURE_DIR"
mkdir -p "${FEATURE_DIR}/判断記録"
TEMPLATE="$REPO_ROOT/.spec-runner/templates/UC-N-ユースケース名.md"
if [[ -f "$TEMPLATE" ]]; then
  sed "s/UC-N/${NEXT_UC}/g; s/{ユースケース名}/${DOC_TITLE}/g" "$TEMPLATE" > "$UC_DOC"
  echo "Created: $UC_DOC"
else
  touch "$UC_DOC"
  echo "# ${NEXT_UC}: ${DOC_TITLE}" >> "$UC_DOC"
  echo "Created: $UC_DOC"
fi

echo ""
echo "UC 仕様の準備ができました（現在のブランチは変更していません）。次のステップに進んでください。"
