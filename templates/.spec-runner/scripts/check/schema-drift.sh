#!/usr/bin/env bash
# ドリフト確認 --スキーマ（spec.md セクション 11）
# ① DBML テーブル名の禁止語 ② テーブル note の集約参照 ③ 集約.md 対応テーブル↔DBML ④ 必須カラム

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

DBML="docs/05_インフラ設計/schema.dbml"
AGGREGATES="docs/03_ドメイン設計/集約.md"
DICT="docs/03_ドメイン設計/ユビキタス言語辞書.md"
errors=0

[[ -f "$DBML" ]] || { echo "SCHEMA_DRIFT: $DBML が存在しません" >&2; exit 1; }

# DBML 内のテーブル名一覧を取得（Table name { の形式）
get_dbml_tables() {
  grep -E '^Table [a-zA-Z_][a-zA-Z0-9_]*' "$DBML" 2>/dev/null | sed 's/^Table \([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/' || true
}

# ① DBML テーブル名に禁止語が含まれていないか
if [[ -f "$DICT" ]] && command -v yq >/dev/null 2>&1; then
  while IFS= read -r -d '' forbidden; do
    [[ -z "$forbidden" ]] && continue
    while IFS= read -r table; do
      [[ -z "$table" ]] && continue
      if echo "$table" | grep -qi "$forbidden"; then
        echo "SCHEMA_TERM_DRIFT: テーブル「$table」に禁止語「$forbidden」が含まれています" >&2
        errors=$((errors+1))
      fi
    done < <(get_dbml_tables)
  done < <(yq '.terms[]? | select(.forbidden != null) | .forbidden[]?' "$DICT" -r -0 2>/dev/null || true)
fi

# ② 各テーブルの Note に集約参照（docs/03_ドメイン設計 または 集約）が含まれるか
while IFS= read -r table; do
  [[ -z "$table" ]] && continue
  block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null || true)
  if ! echo "$block" | grep -qE 'docs/03_ドメイン設計|集約\.md'; then
    echo "SCHEMA_DRIFT: テーブル「$table」の Note に集約参照がありません（docs/03_ドメイン設計 または 集約.md）" >&2
    errors=$((errors+1))
  fi
done < <(get_dbml_tables)

# ③ 集約.md の「対応テーブル」欄のテーブルが DBML に存在するか
if [[ -f "$AGGREGATES" ]]; then
  # 対応テーブルセクション内の `tablename` を抽出（| `name` | の形式）
  mapping_tables=$(sed -n '/### 対応テーブル/,/^###/p' "$AGGREGATES" 2>/dev/null | grep -oE '\`[a-z_][a-z0-9_]*\`' | tr -d '`' || true)
  for mapping_table in $mapping_tables; do
    if ! get_dbml_tables | grep -qx "$mapping_table"; then
      echo "SCHEMA_DRIFT: 集約.md の対応テーブル「$mapping_table」が DBML に存在しません" >&2
      errors=$((errors+1))
    fi
  done
fi

# ④ 各テーブルに必須カラム id, created_at, updated_at があるか
while IFS= read -r table; do
  [[ -z "$table" ]] && continue
  block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null || true)
  for col in id created_at updated_at; do
    if ! echo "$block" | grep -qE "^\s+${col}\s"; then
      echo "SCHEMA_DRIFT: テーブル「$table」に必須カラム「${col}」がありません" >&2
      errors=$((errors+1))
    fi
  done
done < <(get_dbml_tables)

if [[ $errors -eq 0 ]]; then
  echo "✅ スキーマ整合性チェック: 問題なし"
  exit 0
else
  exit 1
fi
