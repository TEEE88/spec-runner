#!/usr/bin/env bash
# 確認の一括実行（AI 用 / 手動運用は想定しない）。
# デフォルトは「全フェーズで毎回」回せる軽量セット。
# 使用:
#   .spec-runner/scripts/check.sh                 # (= --every) steps.json 整合 + 命名 + 健全性
#   .spec-runner/scripts/check.sh --every
#   .spec-runner/scripts/check.sh --full          # + ドリフト（用語/スキーマ）
#   .spec-runner/scripts/check.sh --フル          # --full の別名
set -e

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

ok() { echo "$1"; }
fail() { echo "$1" >&2; return 1; }

steps_json_path() {
  echo "$REPO_ROOT/.spec-runner/steps/steps.json"
}

get_steps_common_doc() {
  local key="$1"
  local sj v
  sj="$(steps_json_path)"
  [[ -f "$sj" ]] || { fail "STEPS_JSON: $sj が存在しません"; return 1; }
  command -v jq >/dev/null 2>&1 || { fail "STEPS_JSON: jq が必要です"; return 1; }
  v="$(jq -r --arg k "$key" '.common.docs[$k] // empty' "$sj" 2>/dev/null)"
  [[ -n "$v" && "$v" != "null" ]] || { fail "steps.json に common.docs.$key がありません"; return 1; }
  echo "$v"
}

run_steps_json_check() {
  local sj
  sj="$(steps_json_path)"
  [[ -f "$sj" ]] || { fail "STEPS_JSON: $sj が存在しません"; return 1; }
  command -v jq >/dev/null 2>&1 || { fail "STEPS_JSON: jq が必要です（brew install jq）"; return 1; }

  local errors=0
  local required_ids=(
    "charter"
    "uc_spec"
    "domain"
    "architecture_plan"
    "infra_plan"
    "test_design"
    "implement"
    "clarify"
    "analyze"
    "checklist"
    "task_list"
    "other_work"
  )

  dup_ids=$(jq -r '.steps[]?.id // empty' "$sj" | sort | uniq -d || true)
  if [[ -n "${dup_ids:-}" ]]; then
    echo "STEPS_JSON: step id が重複しています:" >&2
    echo "$dup_ids" | sed 's/^/  - /' >&2
    errors=$((errors+1))
  fi

  for id in "${required_ids[@]}"; do
    if ! jq -e --arg id "$id" '.steps[]? | select(.id==$id) | true' "$sj" >/dev/null 2>&1; then
      echo "STEPS_JSON: 必須 step id がありません: $id" >&2
      errors=$((errors+1))
    fi
  done

  while IFS= read -r md; do
    [[ -z "$md" || "$md" == "null" ]] && continue
    base_dir="$(dirname "$sj")"
    if [[ ! -f "$base_dir/$md" ]]; then
      echo "STEPS_JSON: md_file が存在しません: $base_dir/$md" >&2
      errors=$((errors+1))
    fi
  done < <(jq -r '.steps[]?.md_file // empty' "$sj")

  if ! jq -e '.version and (.steps|type=="array") and (.common|type=="object")' "$sj" >/dev/null 2>&1; then
    echo "STEPS_JSON: 形式が不正です（version/common/steps）" >&2
    errors=$((errors+1))
  fi
  if ! jq -e '.common.commands.check and (.common.commands.check|type=="string") and (.common.commands.check|length>0)' "$sj" >/dev/null 2>&1; then
    echo "STEPS_JSON: common.commands.check がありません" >&2
    errors=$((errors+1))
  fi

  if [[ $errors -eq 0 ]]; then
    ok "STEPS_JSON: OK"
    return 0
  else
    return 1
  fi
}

run_naming_check() {
  local errors=0

  # ブランチ名
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "")
  if [[ -n "$branch" ]]; then
    local pj valid bp uc_id_pat other_work
    pj="$REPO_ROOT/.spec-runner/project.json"
    [[ -f "$pj" ]] || { echo "NAMING: project.json がありません: $pj" >&2; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "NAMING: jq が必要です（brew install jq）" >&2; return 1; }
    bp="$(jq -r '.naming.branch_prefix' "$pj")"
    uc_id_pat="$(jq -r '.naming.uc_id_pattern' "$pj")"
    other_work="$(jq -r '.naming.other_work_prefixes[] | . + "/.+"' "$pj" | tr '\n' '|' | sed 's/|$//')"
    if [[ -z "$bp" || "$bp" == "null" || -z "$uc_id_pat" || "$uc_id_pat" == "null" || -z "$other_work" ]]; then
      echo "NAMING: project.json の naming.branch_prefix / uc_id_pattern / other_work_prefixes が不正です" >&2
      errors=$((errors+1))
    else
      valid="^(main|develop|${bp}/(${uc_id_pat}-.+|${other_work})|fix/${uc_id_pat}-.+|release/[0-9]+\\.[0-9]+\\.[0-9]+.*|hotfix/[0-9]+\\.[0-9]+\\.[0-9]+-.+)$"
      if ! echo "$branch" | grep -qE "$valid"; then
        echo "NAMING: ブランチ名「$branch」が規則違反" >&2
        errors=$((errors+1))
      fi
    fi
  fi

  # src フォルダ命名（存在する場合のみ）
  if [[ -d "src" ]]; then
    while IFS= read -r dir; do
      [[ -z "$dir" ]] && continue
      base=$(basename "$dir")
      if ! echo "$base" | grep -qE '^[a-z][a-z0-9-]*$'; then
        echo "NAMING: フォルダ名「$dir」はkebab-caseで命名してください" >&2
        errors=$((errors+1))
      fi
    done < <(find src/ -type d 2>/dev/null || true)
  fi

  if [[ $errors -eq 0 ]]; then
    ok "✅ 命名規則チェック: 問題なし"
    return 0
  else
    return 1
  fi
}

schema_sync_check() {
  # check/schema-sync.sh の移植（最小限）
  local PRISMA="prisma/schema.prisma"
  local DBML
  DBML="$(get_steps_common_doc "infra_root")/schema.dbml"
  local AGGREGATES
  AGGREGATES="$(get_steps_common_doc "domain_root")/集約.md"

  local errors=0
  [[ -f "$PRISMA" ]] || { echo "SCHEMA_SYNC: $PRISMA が存在しません" >&2; return 1; }
  [[ -f "$DBML" ]] || { echo "SCHEMA_SYNC: $DBML が存在しません" >&2; return 1; }

  get_prisma_tables() { grep -E '@@map\\(' "$PRISMA" 2>/dev/null | sed -n 's/.*@@map(\"\\([^\"]*\\)\").*/\\1/p' | sort -u; }
  get_prisma_enums() { grep -E '^enum ' "$PRISMA" 2>/dev/null | sed 's/^enum \\([A-Za-z0-9_]*\\).*/\\1/' | sort -u; }
  get_dbml_tables() { grep -E '^Table [a-zA-Z_][a-zA-Z0-9_]*' "$DBML" 2>/dev/null | sed 's/^Table \\([a-zA-Z_][a-zA-Z0-9_]*\\).*/\\1/' | sort -u; }
  get_dbml_enums() { grep -E '^Enum [a-zA-Z_][a-zA-Z0-9_]*' "$DBML" 2>/dev/null | sed 's/^Enum \\([a-zA-Z_][a-zA-Z0-9_]*\\).*/\\1/' | sort -u; }

  prisma_tables=$(get_prisma_tables)
  dbml_tables=$(get_dbml_tables)
  for t in $prisma_tables; do
    echo "$dbml_tables" | grep -qx "$t" || { echo "SCHEMA_SYNC: Prisma のテーブル「$t」が schema.dbml にありません" >&2; errors=$((errors+1)); }
  done
  for t in $dbml_tables; do
    echo "$prisma_tables" | grep -qx "$t" || { echo "SCHEMA_SYNC: schema.dbml のテーブル「$t」が Prisma にありません" >&2; errors=$((errors+1)); }
  done

  dbml_enum_count=$(get_dbml_enums | wc -l | tr -d ' ')
  prisma_enum_count=$(get_prisma_enums | wc -l | tr -d ' ')
  if [[ "$prisma_enum_count" -gt 0 ]] && [[ "$dbml_enum_count" -eq 0 ]]; then
    echo "SCHEMA_SYNC: Prisma に enum がありますが schema.dbml に Enum がありません" >&2
    errors=$((errors+1))
  fi

  table_has_column() {
    local table="$1" col="$2"
    block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null)
    echo "$block" | grep -qE "^\\s+${col}\\s+"
  }
  get_dbml_column_type() {
    local table="$1" col="$2"
    block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null)
    echo "$block" | grep -E "^\\s+${col}\\s+" | head -1 | awk '{ printf "%s", $2 }'
  }
  get_aggregate_doc_type() {
    local ref="$1"
    grep "| *${ref} *|" "$AGGREGATES" 2>/dev/null | head -1 | awk -F'|' 'NF>=4 { gsub(/^[ \\t]+|[ \\t]+$/, \"\", $4); print $4 }'
  }
  normalize_type() {
    raw=$(printf '%s' "$1" | tr -d '\r\n' | sed 's/^[ \\t]*//; s/[ \\t]*$//; s/ .*//; s/(.*//')
    [[ -z "$raw" ]] && return
    raw=$(echo "$raw" | awk '{ print tolower($0) }')
    [[ "$raw" == varchar* ]] && { echo -n "varchar"; return; }
    ([[ "$raw" == *enum* ]] || [[ "$raw" == *_enum ]]) && { echo -n "enum"; return; }
    case "$raw" in
      uuid|text|timestamptz|date) echo -n "$raw" ;;
      *) echo -n "$raw" ;;
    esac
  }

  if [[ -f "$AGGREGATES" ]]; then
    mapping_tables=$(sed -n '/### 対応テーブル/,/^###/p' "$AGGREGATES" 2>/dev/null | grep -oE '\\`[a-z_][a-z0-9_]*\\`' | tr -d '`' | sort -u)
    for t in $mapping_tables; do
      echo "$dbml_tables" | grep -qx "$t" || { echo "SCHEMA_SYNC: 集約.md の対応テーブル「$t」が schema.dbml にありません" >&2; errors=$((errors+1)); }
    done

    table_col_refs=$(grep -oE '[a-z_][a-z0-9_]*\\.[a-z_][a-z0-9_]*' "$AGGREGATES" 2>/dev/null | grep -v '^schema\\.dbml$' | sort -u)
    while IFS= read -r ref; do
      ref=$(printf '%s' "$ref" | tr -d '\r\n')
      [[ -z "$ref" ]] && continue
      t="${ref%%.*}"; c="${ref#*.}"
      if ! echo "$dbml_tables" | grep -qx "$t"; then
        echo "SCHEMA_SYNC: 集約.md で参照されているテーブル「$t」が schema.dbml にありません" >&2
        errors=$((errors+1))
      elif ! table_has_column "$t" "$c"; then
        echo "SCHEMA_SYNC: 集約.md の「$ref」— schema.dbml のテーブル「$t」にカラム「$c」がありません" >&2
        errors=$((errors+1))
      else
        doc_type=$(get_aggregate_doc_type "$ref" | tr -d '\r\n')
        dbml_type=$(get_dbml_column_type "$t" "$c" | tr -d '\r\n')
        if [[ -n "$doc_type" ]] && [[ -n "$dbml_type" ]]; then
          norm_doc=$(normalize_type "$doc_type" | tr -d '\r\n' | sed 's/^[ \\t]*//; s/[ \\t]*$//')
          norm_dbml=$(normalize_type "$dbml_type" | tr -d '\r\n' | sed 's/^[ \\t]*//; s/[ \\t]*$//')
          if [[ -n "$norm_doc" ]] && [[ -n "$norm_dbml" ]] && [[ "x${norm_doc}" != "x${norm_dbml}" ]]; then
            echo "SCHEMA_SYNC: 集約.md の「${ref}」の型が schema.dbml と不一致（集約: ${doc_type} → ${norm_doc}, DBML: ${dbml_type} → ${norm_dbml}）" >&2
            errors=$((errors+1))
          fi
        fi
      fi
    done <<< "$table_col_refs"
  fi

  if [[ $errors -eq 0 ]]; then
    ok "✅ スキーマ同期チェック: ドキュメントと Prisma は一致しています"
    return 0
  else
    echo "SCHEMA_SYNC: $errors 件の不整合" >&2
    return 1
  fi
}

schema_drift_check() {
  local DBML
  DBML="$(get_steps_common_doc "infra_root")/schema.dbml"
  local AGGREGATES
  AGGREGATES="$(get_steps_common_doc "domain_root")/集約.md"
  local DICT
  DICT="$(get_steps_common_doc "domain_root")/ユビキタス言語辞書.md"
  local errors=0

  [[ -f "$DBML" ]] || { echo "SCHEMA_DRIFT: $DBML が存在しません" >&2; return 1; }

  get_dbml_tables() { grep -E '^Table [a-zA-Z_][a-zA-Z0-9_]*' "$DBML" 2>/dev/null | sed 's/^Table \\([a-zA-Z_][a-zA-Z0-9_]*\\).*/\\1/' || true; }

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

  while IFS= read -r table; do
    [[ -z "$table" ]] && continue
    block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null || true)
    if ! echo "$block" | grep -qE 'docs/03_ドメイン設計|集約\\.md'; then
      echo "SCHEMA_DRIFT: テーブル「$table」の Note に集約参照がありません（docs/03_ドメイン設計 または 集約.md）" >&2
      errors=$((errors+1))
    fi
  done < <(get_dbml_tables)

  if [[ -f "$AGGREGATES" ]]; then
    mapping_tables=$(sed -n '/### 対応テーブル/,/^###/p' "$AGGREGATES" 2>/dev/null | grep -oE '\\`[a-z_][a-z0-9_]*\\`' | tr -d '`' || true)
    for mapping_table in $mapping_tables; do
      get_dbml_tables | grep -qx "$mapping_table" || { echo "SCHEMA_DRIFT: 集約.md の対応テーブル「$mapping_table」が DBML に存在しません" >&2; errors=$((errors+1)); }
    done
  fi

  while IFS= read -r table; do
    [[ -z "$table" ]] && continue
    block=$(awk "/^Table ${table}[^a-zA-Z0-9_]/,/^}/" "$DBML" 2>/dev/null || true)
    for col in id created_at updated_at; do
      echo "$block" | grep -qE "^\\s+${col}\\s" || { echo "SCHEMA_DRIFT: テーブル「$table」に必須カラム「${col}」がありません" >&2; errors=$((errors+1)); }
    done
  done < <(get_dbml_tables)

  if [[ $errors -eq 0 ]]; then
    ok "✅ スキーマ整合性チェック: 問題なし"
    return 0
  else
    return 1
  fi
}

run_health_check() {
  local drifts=()
  local current_phase=0
  local current_step_id=""
  local is_quality_step=0

  # フェーズに応じてチェック強度を段階適用する
  if [[ -x ".spec-runner/scripts/spec-runner-core.sh" ]] && command -v jq >/dev/null 2>&1; then
    current_phase="$(.spec-runner/scripts/spec-runner-core.sh --json 2>/dev/null | jq -r '.phase // 0' 2>/dev/null)"
    [[ -n "$current_phase" && "$current_phase" != "null" ]] || current_phase=0
    current_step_id="$(.spec-runner/scripts/spec-runner-core.sh --json 2>/dev/null | jq -r '.step_id // empty' 2>/dev/null)"
  fi
  [[ "$current_step_id" == "clarify" || "$current_step_id" == "analyze" ]] && is_quality_step=1

  UC_ROOT="$(get_steps_common_doc "uc_root")"
  DOMAIN_ROOT="$(get_steps_common_doc "domain_root")"
  ARCH_ROOT="$(get_steps_common_doc "architecture_root")"
  INFRA_ROOT="$(get_steps_common_doc "infra_root")"
  OPENAPI_PATH="$(get_steps_common_doc "openapi")"

  for f in "$UC_ROOT"/*/UC-*.md; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" .md)
    if ! grep -qE '受入条件|成功基準|前提:|操作:|期待:|\\|[[:space:]]*前提[[:space:]]*\\|[[:space:]]*操作[[:space:]]*\\|[[:space:]]*期待[[:space:]]*\\|' "$f" 2>/dev/null; then
      drifts+=("UC ${base}: 受入条件または成功基準がありません")
    fi
    count=$(grep -c '\\[要確認:' "$f" 2>/dev/null || echo 0)
    count=$(echo "$count" | head -1 | tr -cd '0-9'); count=${count:-0}
    [[ "$count" -gt 3 ]] && drifts+=("UC ${base}: [要確認: が ${count} 個（3個以下にすること）")
    # `## 実装方針` / `## タスク(一覧)` は実装計画以降で埋まる想定。
    # ただし `clarify/analyze` は「任意フェーズで挿入」されるため、
    # 実装計画が回っていない（＝生成物がまだ無い）タイミングで先回りで落とさない。
    if [[ "$current_phase" -ge 3 && "$is_quality_step" -eq 0 ]]; then
      grep -qE '^## 実装方針' "$f" 2>/dev/null || drifts+=("UC ${base}: 「## 実装方針」の見出しがありません（UC 仕様書の一番下に記載すること）")
      grep -qE '^## タスク一覧|^## タスク\\b' "$f" 2>/dev/null || drifts+=("UC ${base}: 「## タスク」または「## タスク一覧」の見出しがありません（UC 仕様書の一番下に記載すること）")
    fi
  done

  if [[ "$current_phase" -ge 3 && "$is_quality_step" -eq 0 ]]; then
    adr_count=$(find "$ARCH_ROOT/設計判断記録" -name "*.md" 2>/dev/null | wc -l)
    [[ "${adr_count:-0}" -lt 1 ]] && drifts+=("ADR が 1 件もありません（設計判断記録）")
  fi

  if [[ "$current_phase" -ge 2 && "$is_quality_step" -eq 0 ]]; then
    if [[ ! -f "$DOMAIN_ROOT/ユビキタス言語辞書.md" ]]; then
      drifts+=("ユビキタス言語辞書.md が存在しません")
    else
      grep -qE '禁止語|forbidden' "$DOMAIN_ROOT/ユビキタス言語辞書.md" 2>/dev/null || drifts+=("ユビキタス言語辞書に禁止語欄が定義されていません")
    fi
    if [[ -f "$DOMAIN_ROOT/集約.md" ]]; then
      grep -q '対応テーブル' "$DOMAIN_ROOT/集約.md" 2>/dev/null || drifts+=("集約.md に「対応テーブル」欄がありません")
    fi
  fi

  if [[ ! -f ".spec-runner/grade-history.json" ]]; then
    drifts+=(".spec-runner/grade-history.json がありません")
  elif command -v jq >/dev/null 2>&1; then
    grade=$(jq -r '.current_grade' .spec-runner/grade-history.json)
    [[ -n "$grade" && "$grade" != "null" ]] || drifts+=("grade-history.json の current_grade が未設定です")
    if [[ "$grade" == "A" && "$current_phase" -ge 4 && "$is_quality_step" -eq 0 ]]; then
      [[ ! -f "$INFRA_ROOT/schema.dbml" ]] && drifts+=("Grade A 必須: schema.dbml が存在しません")
      schema_sync_check >/dev/null 2>&1 || drifts+=("Prisma と schema.dbml のテーブルが一致していません（スキーマ同期チェック）")
    fi
  fi

  if [[ "$current_phase" -ge 3 && "$is_quality_step" -eq 0 ]]; then
    [[ ! -f "$OPENAPI_PATH" ]] && drifts+=("openapi.yaml が存在しません")
  fi

  if [[ ${#drifts[@]} -eq 0 ]]; then
    ok "健全性確認: 問題なし"
    return 0
  else
    echo "健全性確認: ${#drifts[@]} 件の指摘" >&2
    for d in "${drifts[@]}"; do echo "  - $d" >&2; done
    return 1
  fi
}

run_drift_terms() {
  local DOMAIN_ROOT ARCH_ROOT
  DOMAIN_ROOT="$(get_steps_common_doc "domain_root")"
  ARCH_ROOT="$(get_steps_common_doc "architecture_root")"
  DICT="${DOMAIN_ROOT}/ユビキタス言語辞書.md"
  NAMING="${ARCH_ROOT}/命名規則.md"
  [[ -f "$DICT" ]] || { ok "ドリフト確認（用語）: ユビキタス言語辞書がありません。スキップします。"; return 0; }

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

  [[ $found -gt 0 ]] && return 1
  ok "✅ 禁止語チェック: 問題なし"
  return 0
}

MODE="${1:-}"
case "$MODE" in
  --every|"")
    run_steps_json_check && run_naming_check && run_health_check
    ;;
  --full|--フル)
    run_steps_json_check && run_naming_check && run_health_check && run_drift_terms && schema_drift_check
    ;;
  *)
    fail "Usage: check.sh [--every|--full|--フル]"
    ;;
esac
