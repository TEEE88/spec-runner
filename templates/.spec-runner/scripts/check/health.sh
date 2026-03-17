#!/usr/bin/env bash
# 健全性確認（spec.md セクション 12）。--形式=json で JSON を標準出力に出す。

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

drifts=()

# 設計書品質
for f in docs/02_ユースケース仕様/*/UC-*.md; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f" .md)
  if ! grep -qE '受入条件|成功基準|Given|When|Then|EARS' "$f" 2>/dev/null; then
    drifts+=("UC ${base}: 受入条件または成功基準がありません")
  fi
  count=$(grep -c '\[要確認:' "$f" 2>/dev/null || echo 0)
  count=$(echo "$count" | head -1 | tr -cd '0-9'); count=${count:-0}
  if [[ "$count" -gt 3 ]]; then
    drifts+=("UC ${base}: [要確認: が ${count} 個（3個以下にすること）")
  fi
  # 実装方針・タスクは UC の .md の一番下に記載する。
  if ! grep -qE '^## 実装方針' "$f" 2>/dev/null; then
    drifts+=("UC ${base}: 「## 実装方針」の見出しがありません（UC 仕様書の一番下に記載すること）")
  fi
  if ! grep -qE '^## タスク一覧|^## タスク\b' "$f" 2>/dev/null; then
    drifts+=("UC ${base}: 「## タスク」または「## タスク一覧」の見出しがありません（UC 仕様書の一番下に記載すること）")
  fi
done

adr_count=$(find docs/04_アーキテクチャ/設計判断記録 -name "*.md" 2>/dev/null | wc -l)
[[ "${adr_count:-0}" -lt 1 ]] && drifts+=("ADR が 1 件もありません（設計判断記録）")

if [[ ! -f "docs/03_ドメイン設計/ユビキタス言語辞書.md" ]]; then
  drifts+=("ユビキタス言語辞書.md が存在しません")
else
  if ! grep -qE '禁止語|forbidden' "docs/03_ドメイン設計/ユビキタス言語辞書.md" 2>/dev/null; then
    drifts+=("ユビキタス言語辞書に禁止語欄が定義されていません")
  fi
fi

if [[ -f "docs/03_ドメイン設計/集約.md" ]]; then
  if ! grep -q '対応テーブル' "docs/03_ドメイン設計/集約.md" 2>/dev/null; then
    drifts+=("集約.md に「対応テーブル」欄がありません")
  fi
fi

if [[ -f ".spec-runner/grade-history.json" ]] && command -v jq >/dev/null 2>&1; then
  grade=$(jq -r '.current_grade // ""' .spec-runner/grade-history.json 2>/dev/null)
  if [[ "$grade" == "A" ]]; then
    [[ ! -f "docs/05_インフラ設計/schema.dbml" ]] && drifts+=("Grade A 必須: schema.dbml が存在しません")
    # ドキュメントと Prisma / マイグレーション結果の一致
    if [[ -f "$(dirname "$0")/schema-sync.sh" ]]; then
      "$(dirname "$0")/schema-sync.sh" >/dev/null 2>&1 || drifts+=("Prisma と schema.dbml のテーブルが一致していません（spec-runner 健全性確認 または .spec-runner/scripts/check/schema-sync.sh で詳細確認）")
    fi
    # schema-drift（禁止語・集約参照・必須カラム）は任意。必要なら spec-runner ドリフト確認 --スキーマ を実行
  fi
fi

[[ ! -f "docs/06_API仕様/openapi.yaml" ]] && drifts+=("openapi.yaml が存在しません")

# プロセス品質
branch=$(git branch --show-current 2>/dev/null || echo "")
bp="feature"
other_work="work/.+|infra/.+|cicd/.+"
if [[ -f "$REPO_ROOT/.spec-runner/project.json" ]] && command -v jq >/dev/null 2>&1; then
  p=$(jq -r '.naming.branch_prefix // empty' "$REPO_ROOT/.spec-runner/project.json" 2>/dev/null); [[ -n "$p" ]] && bp="$p"
  ow=$(jq -r '.naming.other_work_prefixes[]? | . + "/.+"' "$REPO_ROOT/.spec-runner/project.json" 2>/dev/null | tr '\n' '|' | sed 's/|$//'); [[ -n "$ow" ]] && other_work="$ow"
fi
valid_branch="^(main|develop|${bp}/(UC-[0-9]{3}-.+|${other_work})|fix/UC-[0-9]{3}-.+|release/[0-9]+\.[0-9]+\.[0-9]+.*|hotfix/[0-9]+\.[0-9]+\.[0-9]+-.+)\$"
if [[ -n "$branch" ]] && ! echo "$branch" | grep -qE "$valid_branch"; then
  drifts+=("ブランチ名が規則違反: $branch")
fi

# JSON 出力（jq がなければ手組み）
build_json() {
  local i
  echo -n '{"drifts":['
  for i in "${!drifts[@]}"; do
    [[ $i -gt 0 ]] && echo -n ','
    # 簡易エスケープ
    s="${drifts[$i]}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo -n "\"$s\""
  done
  echo -n '],"phase":"ok","grade":"ok"}'
}

if [[ "$*" == *"--形式=json"* ]] || [[ "$*" == *"--形式"="json"* ]]; then
  build_json
  [[ ${#drifts[@]} -eq 0 ]] && exit 0 || exit 1
fi

# テキスト出力
if [[ ${#drifts[@]} -eq 0 ]]; then
  echo "健全性確認: 問題なし"
  exit 0
else
  echo "健全性確認: ${#drifts[@]} 件の指摘" >&2
  for d in "${drifts[@]}"; do echo "  - $d" >&2; done
  exit 1
fi
