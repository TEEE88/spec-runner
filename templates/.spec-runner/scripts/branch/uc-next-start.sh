#!/usr/bin/env bash
# 次の UC を開始する: main に切り替え、feature/UC-N-xxx ブランチを作成する。
# 使用例:
#   ./uc-next-start.sh                    # 次 UC 番号を自動検出。説明はプロンプトまたは "next-uc" で作成
#   ./uc-next-start.sh task-update        # 次 UC 番号 + 説明 "task-update" でブランチ作成
#   ./uc-next-start.sh task-update 認証    # 次 UC 番号 + 説明 + カテゴリ
#   ./uc-next-start.sh UC-2 task-update   # 指定 UC + 説明
#   ./uc-next-start.sh UC-2 task-update 認証 # 指定 UC + 説明 + カテゴリ
#   ./uc-next-start.sh --yes task-update  # 確認なしで実行
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
    *)        ARGS+=("$a") ;;
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
DESC=""
CATEGORY=""

# ファイル題名は日本語優先にするため、スクリプト引数の「生の説明」を保持する
RAW_DESC=""
if [[ ${#ARGS[@]} -ge 2 ]] && [[ "${ARGS[0]}" =~ ^${UC_ID_RE}$ ]]; then
  NEXT_UC="${ARGS[0]}"
  DESC="${ARGS[1]}"
  RAW_DESC="${ARGS[1]}"
  CATEGORY="${ARGS[2]:-}"
elif [[ ${#ARGS[@]} -ge 1 ]]; then
  DESC="${ARGS[0]}"
  RAW_DESC="${ARGS[0]}"
  CATEGORY="${ARGS[1]:-}"
fi

# 説明が無ければデフォルト（next-uc や UC 番号ベース）
if [[ -z "$DESC" ]]; then
  if [[ "$YES_MODE" == true ]]; then
    DESC="next-uc"
  else
    echo "次の UC 用ブランチを作成します。"
    echo "  UC: $NEXT_UC"
    echo -n "  説明（英数字・ハイフン推奨。日本語のみの場合は uc-001 等にフォールバック。Enter で \"next-uc\"）: "
    read -r DESC
    DESC="${DESC:-next-uc}"
  fi
fi

# 説明は英小文字・ハイフン（Git ブランチ名は ASCII のみ）。日本語など非 ASCII はサニタイズで除去される
# macOS(BSD sed) でも動くように、連続ハイフンは 's/--*/-/g' で圧縮する
DESC=$(echo "$DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//' | sed 's/-*$//')
# サニタイズ後に空（日本語のみの説明など）の場合は UC 番号ベースのスラグでフォールバック
[[ -z "$DESC" ]] && DESC="uc-$(echo "$NEXT_UC" | sed 's/^UC-//')"
BRANCH_NAME="${BRANCH_PREFIX}/${NEXT_UC}-${DESC}"

# UC 仕様書ファイル名は必ず日本語にする（題名が ASCII のみなら「要確認」にする）
DOC_TITLE="$RAW_DESC"
if [[ -z "$DOC_TITLE" ]]; then
  DOC_TITLE="要確認"
else
  # 非ASCIIが無い（= 英数字/記号のみ）なら、日本語題名が無い扱いにして要確認へ
  if echo "$DOC_TITLE" | LC_ALL=C grep -q '^[ -~]*$'; then
    DOC_TITLE="要確認"
  fi
fi
# ファイル名に危険な文字が入らないように除去（日本語は許可）
DOC_TITLE=$(echo "$DOC_TITLE" | sed 's/[\\\\\\/\\:\\*\\?\\\"\\<\\>\\|]/ /g' | sed 's/[[:space:]]\\+/ /g' | sed 's/^ *//; s/ *$//')
[[ -z "$DOC_TITLE" ]] && DOC_TITLE="要確認"

# カテゴリ（省略時はデフォルト）。日本語カテゴリは許可し、危険文字だけ除去。
CATEGORY="${CATEGORY:-ユースケース}"
CATEGORY=$(echo "$CATEGORY" | sed 's/[^a-zA-Z0-9_ーぁ-んァ-ン一-龥\-]//g')
[[ -z "$CATEGORY" ]] && CATEGORY="ユースケース"

if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
  echo "Error: ブランチ '$BRANCH_NAME' は既に存在します。" >&2
  exit 1
fi

CURRENT=$(git branch --show-current 2>/dev/null || echo "")
MAIN_BRANCH="main"
if ! git rev-parse --verify "$MAIN_BRANCH" >/dev/null 2>&1; then
  MAIN_BRANCH="master"
  if ! git rev-parse --verify "$MAIN_BRANCH" >/dev/null 2>&1; then
    echo "Error: main も master も存在しません。" >&2
    exit 1
  fi
fi

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
