#!/usr/bin/env bash
# ドキュメントとマイグレーション結果の一致を検証する。
# ① Prisma スキーマ ↔ schema.dbml のテーブル・ENUM 一致
# ② 集約.md の「対応テーブル」に登場するテーブルが schema.dbml に存在するか
# ③ 設計書の「テーブル.カラム」の使い方・型が schema.dbml の定義と一致するか（集約.md の型列は本スクリプトの正規化ルールで比較）

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

PRISMA="prisma/schema.prisma"
DBML="docs/05_インフラ設計/schema.dbml"
AGGREGATES="docs/03_ドメイン設計/集約.md"
errors=0

[[ -f "$PRISMA" ]] || { echo "SCHEMA_SYNC: $PRISMA が存在しません" >&2; exit 1; }
[[ -f "$DBML" ]] || { echo "SCHEMA_SYNC: $DBML が存在しません" >&2; exit 1; }

# Prisma の @@map("table_name") からテーブル名一覧を取得
get_prisma_tables() {
  grep -E '@@map\(' "$PRISMA" 2>/dev/null | sed -n 's/.*@@map("\([^"]*\)").*/\1/p' | sort -u
}

# Prisma の enum 名を取得（DBML では status_enum のように _enum 付きのことが多い）
get_prisma_enums() {
  grep -E '^enum ' "$PRISMA" 2>/dev/null | sed 's/^enum \([A-Za-z0-9_]*\).*/\1/' | sort -u
}

# DBML の Table 名一覧を取得
get_dbml_tables() {
  grep -E '^Table [a-zA-Z_][a-zA-Z0-9_]*' "$DBML" 2>/dev/null | sed 's/^Table \([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/' | sort -u
}

# DBML の Enum 名一覧を取得
get_dbml_enums() {
  grep -E '^Enum [a-zA-Z_][a-zA-Z0-9_]*' "$DBML" 2>/dev/null | sed 's/^Enum \([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/' | sort -u
}

# テーブル一致チェック
prisma_tables=$(get_prisma_tables)
dbml_tables=$(get_dbml_tables)

for t in $prisma_tables; do
  if ! echo "$dbml_tables" | grep -qx "$t"; then
    echo "SCHEMA_SYNC: Prisma のテーブル「$t」が schema.dbml にありません" >&2
    errors=$((errors+1))
  fi
done
for t in $dbml_tables; do
  if ! echo "$prisma_tables" | grep -qx "$t"; then
    echo "SCHEMA_SYNC: schema.dbml のテーブル「$t」が Prisma にありません" >&2
    errors=$((errors+1))
  fi
done

# ENUM は Prisma が PascalCase・DBML が snake_case_enum のため、DBML に Enum が存在するかだけ確認
# （値の一致までは見ない。テーブル一致で運用のずれは検知できる）
dbml_enum_count=$(get_dbml_enums | wc -l | tr -d ' ')
prisma_enum_count=$(get_prisma_enums | wc -l | tr -d ' ')
if [[ "$prisma_enum_count" -gt 0 ]] && [[ "$dbml_enum_count" -eq 0 ]]; then
  echo "SCHEMA_SYNC: Prisma に enum がありますが schema.dbml に Enum がありません" >&2
  errors=$((errors+1))
fi

# DBML 内で指定テーブルが指定カラムを持つか（Table ブロック内の行で「  col  type」を検出）
table_has_column() {
  local table="$1"
  local col="$2"
  local block
  block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null)
  echo "$block" | grep -qE "^\s+${col}\s+"
}

# DBML 内の指定テーブル.カラムの型を取得（2番目のトークン。例: uuid, varchar(200), status_enum）
get_dbml_column_type() {
  local table="$1"
  local col="$2"
  local block
  block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null)
  echo "$block" | grep -E "^\s+${col}\s+" | head -1 | awk '{ printf "%s", $2 }'
}

# 集約.md の対応テーブル表で table.column の行から「型」列（| 区切り4番目）を取得
get_aggregate_doc_type() {
  local ref="$1"
  grep "| *${ref} *|" "$AGGREGATES" 2>/dev/null | head -1 | awk -F'|' 'NF>=4 {
    gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4
  }'
}

# 型を正規化して比較用に統一（uuid/varchar/text/timestamptz/date/enum）
# 正規化後: uuid | varchar | text | timestamptz | date | enum
normalize_type() {
  local raw
  raw=$(printf '%s' "$1" | tr -d '\r\n' | sed 's/^[ \t]*//; s/[ \t]*$//; s/ .*//; s/(.*//')
  [[ -z "$raw" ]] && return
  raw=$(echo "$raw" | awk '{ print tolower($0) }')
  if [[ "$raw" == varchar* ]]; then echo -n "varchar"; return; fi
  if [[ "$raw" == *enum* ]] || [[ "$raw" == *_enum ]]; then echo -n "enum"; return; fi
  case "$raw" in
    uuid|text|timestamptz|date) echo -n "$raw" ;;
    *) echo -n "$raw" ;;
  esac
}

# 集約.md の「対応テーブル」に登場するテーブルが DBML に存在するか（schema-drift と重複するがここでも確認）
if [[ -f "$AGGREGATES" ]]; then
  mapping_tables=$(sed -n '/### 対応テーブル/,/^###/p' "$AGGREGATES" 2>/dev/null | grep -oE '\`[a-z_][a-z0-9_]*\`' | tr -d '`' | sort -u)
  for t in $mapping_tables; do
    if ! echo "$dbml_tables" | grep -qx "$t"; then
      echo "SCHEMA_SYNC: 集約.md の対応テーブル「$t」が schema.dbml にありません" >&2
      errors=$((errors+1))
    fi
  done

  # 設計書の「テーブル.カラム」の使い方が schema.dbml の定義と一致するか
  # 集約.md の「DBテーブル.カラム」列から table.column を抽出（"schema.dbml" は見出し由来のため除外）
  table_col_refs=$(grep -oE '[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*' "$AGGREGATES" 2>/dev/null | grep -v '^schema\.dbml$' | sort -u)
  while IFS= read -r ref; do
    ref=$(printf '%s' "$ref" | tr -d '\r\n')
    [[ -z "$ref" ]] && continue
    t="${ref%%.*}"
    c="${ref#*.}"
    [[ -z "$t" || -z "$c" ]] && continue
    if ! echo "$dbml_tables" | grep -qx "$t"; then
      echo "SCHEMA_SYNC: 集約.md で参照されているテーブル「$t」が schema.dbml にありません" >&2
      errors=$((errors+1))
    elif ! table_has_column "$t" "$c"; then
      echo "SCHEMA_SYNC: 集約.md の「$ref」— schema.dbml のテーブル「$t」にカラム「$c」がありません" >&2
      errors=$((errors+1))
    else
      # 型の一致（集約.md の「型」列と schema.dbml を正規化して比較）
      doc_type=$(get_aggregate_doc_type "$ref" | tr -d '\r\n')
      dbml_type=$(get_dbml_column_type "$t" "$c" | tr -d '\r\n')
      if [[ -n "$doc_type" ]] && [[ -n "$dbml_type" ]]; then
        norm_doc=$(normalize_type "$doc_type" | tr -d '\r\n' | sed 's/^[ \t]*//; s/[ \t]*$//')
        norm_dbml=$(normalize_type "$dbml_type" | tr -d '\r\n' | sed 's/^[ \t]*//; s/[ \t]*$//')
        if [[ -n "$norm_doc" ]] && [[ -n "$norm_dbml" ]] && [[ "x${norm_doc}" != "x${norm_dbml}" ]]; then
          echo "SCHEMA_SYNC: 集約.md の「${ref}」の型が schema.dbml と不一致（集約: ${doc_type} → ${norm_doc}, DBML: ${dbml_type} → ${norm_dbml}）" >&2
          errors=$((errors+1))
        fi
      fi
    fi
  done <<< "$table_col_refs"
fi

if [[ $errors -eq 0 ]]; then
  echo "✅ スキーマ同期チェック: ドキュメントと Prisma は一致しています"
  exit 0
else
  echo "SCHEMA_SYNC: $errors 件の不整合" >&2
  exit 1
fi
