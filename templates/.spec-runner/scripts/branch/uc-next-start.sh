#!/usr/bin/env bash
# 次の UC を開始する: main に切り替え、feature/UC-NNN-xxx ブランチを作成する。
# 使用例:
#   ./uc-next-start.sh                    # 次 UC 番号を自動検出。説明はプロンプトまたは "next-uc" で作成
#   ./uc-next-start.sh task-update        # 次 UC 番号 + 説明 "task-update" でブランチ作成
#   ./uc-next-start.sh UC-002 task-update # 指定 UC + 説明
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

# 次 UC 番号を取得
NEXT_UC=$("$BRANCH_DIR/uc-next-id.sh")
DESC=""

if [[ ${#ARGS[@]} -ge 2 ]] && [[ "${ARGS[0]}" =~ ^UC-[0-9]{3}$ ]]; then
  NEXT_UC="${ARGS[0]}"
  DESC="${ARGS[1]}"
elif [[ ${#ARGS[@]} -ge 1 ]]; then
  DESC="${ARGS[0]}"
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
DESC=$(echo "$DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//')
# サニタイズ後に空（日本語のみの説明など）の場合は UC 番号ベースのスラグでフォールバック
[[ -z "$DESC" ]] && DESC="uc-$(echo "$NEXT_UC" | sed 's/^UC-//')"
BRANCH_NAME="feature/${NEXT_UC}-${DESC}"

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
"$BRANCH_DIR/create-uc-branch.sh" "$NEXT_UC" "$DESC"
echo ""
echo "次の UC 用ブランチの準備ができました。次のステップに進んでください。"
