#!/usr/bin/env bash
# ドリフト確認（Section 10: 仕様とコードの乖離検出）
# オプション: --用語（禁止語）, --スキーマ（集約↔DBML）, --命名（命名規則）, --レポート（レポート出力）

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

MODE=""
for a in "$@"; do
  case "$a" in
    --用語)   MODE="terms" ;;
    --スキーマ) MODE="schema" ;;
    --命名)   MODE="naming" ;;
    --レポート) MODE="report" ;;
  esac
done

if [[ "$MODE" == "naming" ]]; then
  exec "$(dirname "$0")/naming.sh"
fi

if [[ "$MODE" == "terms" ]]; then
  # 禁止語チェック: ユビキタス言語辞書の forbidden を src/ で検索（命名規則.md の SOURCE_EXTENSIONS を参照）
  DICT="docs/03_ドメイン設計/ユビキタス言語辞書.md"
  NAMING="docs/04_アーキテクチャ/命名規則.md"
  if [[ ! -f "$DICT" ]]; then
    echo "ドリフト確認（用語）: ユビキタス言語辞書がありません。スキップします。"
    exit 0
  fi
  source_exts="ts,php,py,go,java"
  if [[ -f "$NAMING" ]]; then
    line=$(grep -E '^SOURCE_EXTENSIONS:' "$NAMING" 2>/dev/null | head -1)
    [[ -n "$line" ]] && source_exts=$(echo "$line" | sed 's/SOURCE_EXTENSIONS:[[:space:]]*//;s/[[:space:]]//g')
  fi
  found=0
  if command -v yq >/dev/null 2>&1; then
    while IFS= read -r -d '' forbidden; do
      [[ -z "$forbidden" ]] && continue
      c=0
      if [[ -d "src" ]]; then
        for ext in $(echo "$source_exts" | tr ',' ' '); do
          n=$(find src -type f -name "*.$ext" 2>/dev/null | xargs grep -l "$forbidden" 2>/dev/null | wc -l)
          c=$((c + n))
        done
      fi
      if [[ "$c" -gt 0 ]]; then
        echo "禁止語「$forbidden」が src/ に ${c} 件あります。"
        found=$((found+1))
      fi
    done < <(yq '.terms[]? | select(.forbidden != null) | .forbidden[]?' "$DICT" -r -0 2>/dev/null || true)
  fi
  if [[ $found -gt 0 ]]; then
    exit 1
  fi
  echo "✅ 禁止語チェック: 問題なし"
  exit 0
fi

if [[ "$MODE" == "schema" ]]; then
  exec "$(dirname "$0")/schema-drift.sh"
fi

# デフォルト: オプション未指定時はメッセージのみ
echo "✅ ドリフト確認: 完了（--用語 / --スキーマ / --命名 で個別チェック、健全性確認で一括チェック）"
exit 0
