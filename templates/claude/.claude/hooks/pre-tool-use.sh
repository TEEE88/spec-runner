#!/usr/bin/env bash
# =============================================================================
# Claude Code Pre-Tool-Use Hook
# ファイル書き込み前にフェーズを確認し、実装フェーズ以外でのコード生成をブロックする
#
# Claude Code の hooks 仕様:
#   - stdin: JSON {"tool_name": "...", "tool_input": {...}}
#   - exit 0: 許可
#   - exit 2: ブロック（Claude にエラーメッセージを返す）
# =============================================================================

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
STATE_FILE="$PROJECT_ROOT/.spec-runner/state.json"
CONFIG_FILE="$PROJECT_ROOT/.spec-runner/config.sh"

# ステートファイルがなければ素通り（init前は制限しない）
[[ -f "$STATE_FILE" ]] || exit 0

# フレームワーク設定を読み込む（拡張子の設定のため）
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=.spec-runner/config.sh
  source "$CONFIG_FILE"
fi

# デフォルト拡張子（config.sh がない場合）
SOURCE_EXTENSIONS="${SOURCE_EXTENSIONS:-ts tsx js jsx php py rb}"

# stdinからツール情報を読む
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# ファイル書き込み系のツールのみチェック
case "$tool_name" in
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# 設計ドキュメントや設定ファイルへの書き込みは常に許可
case "$file_path" in
  */docs/*|*/CLAUDE.md|*/.spec-runner/state.json|*/scripts/*|*/.github/*|\
  */templates/*|*/03_用語集.md|*.json|*.yml|*.yaml|*.sh|*.lock|\
  */.spec-runner/*|*/node_modules/*|*/vendor/*)
    exit 0
    ;;
esac

# SOURCE_EXTENSIONS を配列に変換して拡張子チェック
phase=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)

# 拡張子チェック: SOURCE_EXTENSIONS に含まれる拡張子のみブロック対象
should_block=false
for ext in $SOURCE_EXTENSIONS; do
  if [[ "$file_path" == *."$ext" ]]; then
    should_block=true
    break
  fi
done

if [[ "$should_block" == "true" ]]; then
  if [[ "$phase" != "implement" && "$phase" != "fix" && "$phase" != "hotfix" ]]; then
    next_cmd=$(case "$phase" in
      require*)       echo "design-high" ;;
      design-high)    echo "design-detail domain" ;;
      design-detail*) echo "design-detail <次のサブフェーズ>" ;;
      test-design)    echo "implement" ;;
      *)              echo "status" ;;
    esac)
    cat <<MSG
{
  "decision": "block",
  "reason": "【フェーズゲート】現在のフェーズは '$phase' です。実装コードの生成は 'implement' フェーズでのみ許可されています。\n\n現在の状態を確認: ./.spec-runner/scripts/spec-runner.sh status\n次のフェーズへ: ./.spec-runner/scripts/spec-runner.sh $next_cmd"
}
MSG
    exit 2
  fi
fi

exit 0
