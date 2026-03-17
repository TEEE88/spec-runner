#!/usr/bin/env bash
# 新規 UC 用ブランチ作成（Section 8-1）
# 使用例: ./create-uc-branch.sh UC-001 order-placement [カテゴリ] [--json]
# ブランチ名: feature/UC-001-order-placement。UC 仕様書: docs/02_ユースケース仕様/<カテゴリ>/UC-001-order-placement.md

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

JSON_MODE=false
ARGS=()
for a in "$@"; do
  case "$a" in
    --json) JSON_MODE=true ;;
    *)      ARGS+=("$a") ;;
  esac
done

# 引数が 1 つ（説明のみ）のときは uc-next-id で UC 番号を取得
if [[ ${#ARGS[@]} -eq 1 ]]; then
  UC_ID=$("$(dirname "$0")/uc-next-id.sh" 2>/dev/null || true)
  [[ -z "$UC_ID" ]] && { echo "Error: uc-next-id の取得に失敗しました" >&2; exit 1; }
  ARGS=("$UC_ID" "${ARGS[0]}")
fi

UC_ID="${ARGS[0]:-}"
DESC="${ARGS[1]:-}"
if [[ -z "$UC_ID" || -z "$DESC" ]]; then
  echo "Usage: $0 <UC-ID> <kebab-description> [カテゴリ] [--json]" >&2
  echo "       $0 <kebab-description>   # UC 番号は自動採番" >&2
  echo "Example: $0 UC-001 order-placement" >&2
  echo "Example: $0 order-placement" >&2
  exit 1
fi
# 第3引数: カテゴリ（省略時はデフォルト）。--json の場合はカテゴリ未指定
CATEGORY="${ARGS[2]:-}"
[[ "${CATEGORY}" == "--json" ]] && CATEGORY=""
# カテゴリ未指定時はデフォルト（英数字・ハイフンのみでサニタイズ）
CATEGORY="${CATEGORY:-ユースケース}"
CATEGORY=$(echo "$CATEGORY" | sed 's/[^a-zA-Z0-9_ーぁ-んァ-ン一-龥\-]//g')
[[ -z "$CATEGORY" ]] && CATEGORY="ユースケース"

# UC-ID 形式: UC-NNN
if ! echo "$UC_ID" | grep -qE '^UC-[0-9]{3}$'; then
  echo "Error: UC-ID must be UC-NNN (e.g. UC-001)" >&2
  exit 1
fi

# 説明は英小文字・ハイフン（Git ブランチ名は ASCII のみ）。日本語など非 ASCII はサニタイズで除去される
DESC=$(echo "$DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//')
# サニタイズ後に空（日本語のみの説明など）の場合は UC 番号ベースのスラグでフォールバック
[[ -z "$DESC" ]] && DESC="uc-$(echo "$UC_ID" | sed 's/^UC-//')"
# ブランチ接頭辞は project.json の naming.branch_prefix（初期化で設定）。無ければ feature
BRANCH_PREFIX="feature"
if [[ -f ".spec-runner/project.json" ]] && command -v jq >/dev/null 2>&1; then
  p=$(jq -r '.naming.branch_prefix // empty' .spec-runner/project.json 2>/dev/null)
  [[ -n "$p" ]] && BRANCH_PREFIX="$p"
fi
BRANCH_NAME="${BRANCH_PREFIX}/${UC_ID}-${DESC}"

# 命名規則チェック（project.json の branch_prefix + UC 形式）。AI 実行前に検証。
valid_uc_pattern="^${BRANCH_PREFIX}/UC-[0-9]{3}-[a-z0-9-]+\$"
if ! echo "$BRANCH_NAME" | grep -qE "$valid_uc_pattern"; then
  echo "Error: ブランチ名が命名規則に合いません: $BRANCH_NAME（期待: ${BRANCH_PREFIX}/UC-NNN-kebab-description）" >&2
  exit 1
fi

if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
  echo "Error: Branch '$BRANCH_NAME' already exists." >&2
  exit 1
fi

git checkout -b "$BRANCH_NAME"
echo "Created branch: $BRANCH_NAME"

# UC 仕様書を docs/02_ユースケース仕様/<カテゴリ>/UC-NNN-xxx.md に作成（1 UC = 1 ファイル）
FEATURE_DIR="docs/02_ユースケース仕様/${CATEGORY}"
UC_DOC="${FEATURE_DIR}/${UC_ID}-${DESC}.md"
mkdir -p "$FEATURE_DIR"
TEMPLATE="$REPO_ROOT/.spec-runner/templates/UC-NNN-ユースケース名.md"
if [[ -f "$TEMPLATE" ]]; then
  sed "s/UC-NNN/${UC_ID}/g; s/{ユースケース名}/${DESC}/g" "$TEMPLATE" > "$UC_DOC"
  echo "Created: $UC_DOC"
else
  touch "$UC_DOC"
  echo "# ${UC_ID}: ${DESC}" >> "$UC_DOC"
  echo "Created: $UC_DOC"
fi

if [[ "$JSON_MODE" == true ]]; then
  SPEC_ABS="$REPO_ROOT/$UC_DOC"
  DIR_ABS="$REPO_ROOT/$FEATURE_DIR"
  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg branch "$BRANCH_NAME" \
      --arg spec_file "$SPEC_ABS" \
      --arg feature_dir "$DIR_ABS" \
      '{BRANCH_NAME:$branch,SPEC_FILE:$spec_file,FEATURE_SPEC:$spec_file,FEATURE_DIR:$feature_dir}'
  else
    printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_SPEC":"%s","FEATURE_DIR":"%s"}\n' \
      "$(printf '%s' "$BRANCH_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
      "$(printf '%s' "$SPEC_ABS" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
      "$(printf '%s' "$SPEC_ABS" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
      "$(printf '%s' "$DIR_ABS" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
fi
