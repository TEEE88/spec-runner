#!/usr/bin/env bash
# 次の UC を開始する: main に切り替え、feature/UC-N-xxx ブランチを作成する。
# 使用例:
#   ./uc-next-start.sh "task-management" "タスク管理機能追加" "タスク管理"
#   ./uc-next-start.sh UC-2 "order-cancel" "注文キャンセル" "注文"
#   ./uc-next-start.sh --yes "task-management" "タスク管理機能追加" "タスク管理"
# 引数仕様（位置引数）:
#   [UC-ID] [SLUG] [TITLE] [CATEGORY]
#   - UC-ID: 省略可（例: UC-2）
#   - SLUG: 必須。ブランチ用の短名（ASCII, kebab-case 推奨）
#   - TITLE: 必須。UC ファイル題名（日本語推奨）
#   - CATEGORY: 必須。docs/02_ユースケース仕様/ 配下のカテゴリ名（日本語可）
# 重要: 空欄の引数は禁止。SLUG/TITLE/CATEGORY は必ず指定する
# 実行後は次のステップに進む旨を案内する。

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
BRANCH_DIR="$(cd "$(dirname "$0")" && pwd)"

YES_MODE=false
ARGS=()
for a in "$@"; do
  case "$a" in
    --yes|-y) YES_MODE=true ;;
    *)
      # 空引数は禁止
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
BRANCH_PREFIX="$(jq -r '.naming.branch_prefix' "$PROJECT_JSON")"
[[ -n "$UC_ID_RE" && "$UC_ID_RE" != "null" && -n "$BRANCH_PREFIX" && "$BRANCH_PREFIX" != "null" ]] || {
  echo "uc-next-start: project.json の naming.uc_id_pattern / branch_prefix が未設定です" >&2
  exit 1
}

next_uc_id() {
  # docs/02_ユースケース仕様/<カテゴリ>/UC-*.md から次に使う UC-N を返す
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
    echo "Usage: .spec-runner/scripts/branch/uc-next-start.sh [UC-ID] \"SLUG\" \"TITLE\" \"CATEGORY\" [--yes]" >&2
    echo "  - UC-ID を指定した場合は SLUG/TITLE/CATEGORY の3引数が必須です" >&2
    exit 1
  }
  NEXT_UC="${ARGS[0]}"
  SLUG="${ARGS[1]}"
  TITLE="${ARGS[2]}"
  CATEGORY="${ARGS[3]}"
else
  [[ ${#ARGS[@]} -eq 3 ]] || {
    echo "Usage: .spec-runner/scripts/branch/uc-next-start.sh [UC-ID] \"SLUG\" \"TITLE\" \"CATEGORY\" [--yes]" >&2
    echo "  - UC-ID は任意、SLUG/TITLE/CATEGORY は必須です（空文字禁止）" >&2
    exit 1
  }
  SLUG="${ARGS[0]}"
  TITLE="${ARGS[1]}"
  CATEGORY="${ARGS[2]}"
fi

# SLUG / TITLE / CATEGORY は必須（UC-ID のみ任意）
if [[ -z "$SLUG" || -z "$TITLE" || -z "$CATEGORY" ]]; then
  echo "Usage: .spec-runner/scripts/branch/uc-next-start.sh [UC-ID] \"SLUG\" \"TITLE\" \"CATEGORY\" [--yes]" >&2
  echo "  - UC-ID は任意、SLUG/TITLE/CATEGORY は必須です（空文字禁止）" >&2
  exit 1
fi

# SLUG は英小文字・ハイフン（Git ブランチ名は ASCII のみ）
# macOS(BSD sed) でも動くように、連続ハイフンは 's/--*/-/g' で圧縮する
SLUG=$(echo "$SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//' | sed 's/-*$//')
if [[ -z "$SLUG" ]]; then
  echo "Error: SLUG は英数字・ハイフンへ正規化可能な値を指定してください（例: task-management）。" >&2
  exit 1
fi
BRANCH_NAME="${BRANCH_PREFIX}/${NEXT_UC}-${SLUG}"

# UC ファイル題名
DOC_TITLE="$TITLE"
# ファイル名に危険な文字が入らないように除去（日本語は許可）
DOC_TITLE=$(echo "$DOC_TITLE" | sed 's/[\\\\\\/\\:\\*\\?\\\"\\<\\>\\|]/ /g' | sed 's/[[:space:]]\\+/ /g' | sed 's/^ *//; s/ *$//')
if [[ -z "$DOC_TITLE" ]]; then
  echo "Error: TITLE が不正です（危険文字除去後に空になりました）。" >&2
  exit 1
fi

# カテゴリは必須。日本語カテゴリは許可し、危険文字だけ除去。
# 文字レンジ指定は sed 実装差で壊れやすいため、危険文字のみを除去する。
CATEGORY=$(echo "$CATEGORY" | sed 's/[\\\/:\*\?"<>|]//g' | sed 's/[[:cntrl:]]//g' | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//; s/ *$//')
if [[ -z "$CATEGORY" ]]; then
  echo "Error: CATEGORY は空にできません。" >&2
  exit 1
fi

if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
  echo "Error: ブランチ '$BRANCH_NAME' は既に存在します。" >&2
  exit 1
fi

CURRENT=$(git branch --show-current 2>/dev/null || echo "")
MAIN_BRANCH=""

# 1) origin/HEAD からデフォルトブランチを取得
if git symbolic-ref -q --short refs/remotes/origin/HEAD >/dev/null 2>&1; then
  MAIN_BRANCH="$(git symbolic-ref -q --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
fi
# 2) main / master をフォールバック
if [[ -z "$MAIN_BRANCH" ]]; then
  if git rev-parse --verify "main" >/dev/null 2>&1; then
    MAIN_BRANCH="main"
  elif git rev-parse --verify "master" >/dev/null 2>&1; then
    MAIN_BRANCH="master"
  fi
fi
# 3) どれも無ければ現在ブランチ（初期ブランチ名が trunk/develop 等のケース）
if [[ -z "$MAIN_BRANCH" ]]; then
  MAIN_BRANCH="${CURRENT:-}"
fi
[[ -n "$MAIN_BRANCH" ]] || { echo "Error: ベースブランチを特定できません（main/master/current が見つかりません）。" >&2; exit 1; }

if [[ "$YES_MODE" != true ]]; then
  echo "次の UC を開始する準備をします。"
  echo "  $MAIN_BRANCH にチェックアウトし、ブランチ \"$BRANCH_NAME\" を作成します。"
  echo -n "  実行してよろしいですか？ [y/N]: "
  read -r ans
  case "$ans" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "キャンセルしました。"; exit 0 ;;
  esac
fi

git checkout "$MAIN_BRANCH"
git pull --ff-only 2>/dev/null || true

# ブランチ作成 + UC 仕様書作成（統合）
UC_ID_PATTERN="^${UC_ID_RE}$"
if ! echo "$NEXT_UC" | grep -qE "$UC_ID_PATTERN"; then
  echo "Error: UC-ID が命名規則に合いません: $NEXT_UC（期待: $UC_ID_PATTERN）" >&2
  exit 1
fi
valid_uc_pattern="^${BRANCH_PREFIX}/${UC_ID_RE}-[a-z0-9-]+\$"
if ! echo "$BRANCH_NAME" | grep -qE "$valid_uc_pattern"; then
  echo "Error: ブランチ名が命名規則に合いません: $BRANCH_NAME（期待: ${BRANCH_PREFIX}/<UC-ID>-kebab-description）" >&2
  exit 1
fi

git checkout -b "$BRANCH_NAME"
echo "Created branch: $BRANCH_NAME"

FEATURE_DIR="docs/02_ユースケース仕様/${CATEGORY}"
UC_DOC="${FEATURE_DIR}/${NEXT_UC}-${DOC_TITLE}.md"
mkdir -p "$FEATURE_DIR"
# UC ごとの判断ログ置き場（任意だが、作成しておくと運用が安定する）
mkdir -p "${FEATURE_DIR}/判断記録"
# テンプレ: 修正・改善は .spec-runner/templates/UC-N-ユースケース名.md を編集。プレースホルダ UC-N → UC番号, {ユースケース名} → 題名
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
echo "次の UC 用ブランチの準備ができました。次のステップに進んでください。"
