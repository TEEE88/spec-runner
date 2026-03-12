#!/usr/bin/env bash
# =============================================================================
# spec-runner.sh — ドメイン駆動AI開発 フェーズゲートシステム
# =============================================================================
# このスクリプトが「本当の強制」を担う。
# Claude CodeはCLAUDE.mdを読んでルールを「知る」が、スキップできる。
# このスクリプトはシェルレベルで実行を拒否するため、AIも人間もスキップできない。
#
# 使い方:
#   ./.spec-runner/scripts/spec-runner.sh init              … 詳細設定の対話のみ
#   ./.spec-runner/scripts/spec-runner.sh init <ユースケース名> [集約名]  … 設定後ユースケース作成
#   ./.spec-runner/scripts/spec-runner.sh require
#   ./.spec-runner/scripts/spec-runner.sh design-high
#   ./.spec-runner/scripts/spec-runner.sh design-detail <サブフェーズ: domain|usecase|table|infra>
#   ./.spec-runner/scripts/spec-runner.sh test-design
#   ./.spec-runner/scripts/spec-runner.sh implement
#   ./.spec-runner/scripts/spec-runner.sh status
#   ./.spec-runner/scripts/spec-runner.sh fix <修正内容>
#   ./.spec-runner/scripts/spec-runner.sh hotfix <内容>
#   ./.spec-runner/scripts/spec-runner.sh review-pass <ドキュメントパス>
#   ./.spec-runner/scripts/spec-runner.sh complete
# =============================================================================

set -euo pipefail

# ── 定数 ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .spec-runner/scripts/ にいる場合は PROJECT_ROOT は 2 階層上、そうでなければ 1 階層上（旧レイアウト）
if [[ "$SCRIPT_DIR" == */.spec-runner/scripts ]]; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  SPEC_RUNNER_DIR="$PROJECT_ROOT/.spec-runner"
else
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  SPEC_RUNNER_DIR="$PROJECT_ROOT"
fi
STATE_FILE="$PROJECT_ROOT/.spec-runner/state.json"
DEBT_FILE="$PROJECT_ROOT/docs/振り返り/負債.md"
GLOSSARY="$PROJECT_ROOT/docs/03_用語集.md"

# ── フレームワーク設定を読み込む ───────────────────────────────────────────────
# npx spec-runner によって生成された .spec-runner/config.sh を読み込む
# これによりフレームワーク依存の設定（拡張子・パス等）が外部化される
CONFIG_FILE="$PROJECT_ROOT/.spec-runner/config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=.spec-runner/config.sh
  source "$CONFIG_FILE"
else
  # .spec-runner/config.sh がない場合のデフォルト値
  SOURCE_EXTENSIONS="${SOURCE_EXTENSIONS:-ts tsx js jsx php py rb}"
  DOMAIN_PATH="${DOMAIN_PATH:-src/domain}"
  USECASE_PATH="${USECASE_PATH:-src/useCase}"
  INFRA_PATH="${INFRA_PATH:-src/infrastructure}"
fi

# ── カラー出力 ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()    { echo -e "${GREEN}✓${NC} $*"; }
fail()  { echo -e "${RED}✗${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
info()  { echo -e "${CYAN}ℹ${NC} $*"; }
step()  { echo -e "${BOLD}${BLUE}▶${NC} $*"; }
die()   { echo -e "${RED}${BOLD}ERROR:${NC} $*" >&2; exit 1; }

# ── 依存チェック ───────────────────────────────────────────────────────────
require_cmd() {
  command -v "$1" &>/dev/null || die "$1 がインストールされていません"
}
require_cmd jq
require_cmd git

# ── ステート操作 ───────────────────────────────────────────────────────────
state_get() { jq -r ".$1 // empty" "$STATE_FILE" 2>/dev/null || echo ""; }
state_set() {
  local key="$1" val="$2"
  local tmp
  tmp="${STATE_FILE}.tmp.$$"
  jq ".$key = $val" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}
state_set_str() { state_set "$1" "\"$2\""; }
state_set_bool() { state_set "$1" "$2"; }  # true / false

state_init() {
  local usecase="$1" aggregate="${2:-}"
  local branch="feature/uc-$(echo "$usecase" | tr ' ' '-')"
  local agg_branch=""
  [[ -n "$aggregate" ]] && agg_branch="aggregate/$(echo "$aggregate" | tr ' ' '-')"

  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" <<EOF
{
  "usecase": "$usecase",
  "aggregate": "$aggregate",
  "phase": "require",
  "branch": "$branch",
  "aggregate_branch": "$agg_branch",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "gates": {
    "require_approved": false,
    "glossary_checked": false,
    "high_level_reviewed": false,
    "domain_model_reviewed": false,
    "usecase_design_reviewed": false,
    "table_design_reviewed": false,
    "infra_design_reviewed": false,
    "test_design_reviewed": false,
    "test_code_committed": false
  },
  "history": []
}
EOF
}

state_push_history() {
  local msg="$1"
  local tmp
  tmp="${STATE_FILE}.tmp.$$"
  jq ".history += [\"$(date -u +%Y-%m-%dT%H:%M:%SZ): $msg\"]" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ── ステートファイル必須チェック ───────────────────────────────────────────
require_state() {
  [[ -f "$STATE_FILE" ]] || die "作業中のユースケースがありません。まず: ./.spec-runner/scripts/spec-runner.sh init <ユースケース名>"
  local phase
  phase=$(state_get "phase")
  [[ -n "$phase" ]] || die "ステートファイルが壊れています: $STATE_FILE"
}

# ── ゲートチェック関数群 ───────────────────────────────────────────────────

# ドキュメントのfrontmatterからstatusを取得
doc_status() {
  local file="$1"
  [[ -f "$file" ]] || { echo "missing"; return; }
  grep -m1 '^status:' "$file" | sed 's/status: *//' | tr -d '[:space:]' || echo "draft"
}

# ファイル存在チェック（エラーメッセージ付き）
check_file() {
  local file="$1" label="$2"
  if [[ -f "$file" ]]; then
    ok "$label: $file"
    return 0
  else
    fail "$label が存在しません: $file"
    return 1
  fi
}

# ドキュメントステータスチェック
check_status() {
  local file="$1" required_status="$2" label="$3"
  local status
  status=$(doc_status "$file")
  if [[ "$status" == "$required_status" ]] || [[ "$status" == "approved" && "$required_status" == "reviewed" ]]; then
    ok "$label (status: $status)"
    return 0
  else
    fail "$label のステータスが '$status' です。'$required_status' が必要です"
    info "  レビュー後: ./.spec-runner/scripts/spec-runner.sh review-pass $file"
    return 1
  fi
}

# gateフラグチェック
check_gate() {
  local gate="$1" label="$2"
  local val
  val=$(state_get "gates.$gate")
  if [[ "$val" == "true" ]]; then
    ok "$label"
    return 0
  else
    fail "$label（未完了）"
    return 1
  fi
}

# ── debt.md チェック ───────────────────────────────────────────────────────
check_debt() {
  if [[ -f "$DEBT_FILE" ]]; then
    local unchecked
    unchecked=$(grep -c '^\- \[ \]' "$DEBT_FILE" 2>/dev/null; true)
    unchecked="${unchecked:-0}"
    if [[ "${unchecked}" -gt 0 ]]; then
      echo ""
      warn "══════════════════════════════════════════════════════════"
      warn " ドキュメント負債が $unchecked 件あります: $DEBT_FILE"
      warn " 新規開発の前に消化することを推奨します"
      warn "══════════════════════════════════════════════════════════"
      echo ""
      read -r -p "このまま続けますか？ [y/N] " answer
      [[ "$answer" =~ ^[Yy]$ ]] || die "ドキュメント負債を先に解消してください"
    fi
  fi
}

# ── usecase/aggregate のパス計算 ───────────────────────────────────────────
uc_slug()   { echo "$(state_get usecase)" | tr ' ' '-'; }
agg_slug()  { echo "$(state_get aggregate)" | tr ' ' '-'; }
uc_req()    { echo "$PROJECT_ROOT/docs/01_要件/$(uc_slug).md"; }
uc_high()   { echo "$PROJECT_ROOT/docs/02_概要設計/$(uc_slug).md"; }
uc_detail() { echo "$PROJECT_ROOT/docs/03_詳細設計/$(uc_slug)"; }
uc_test()   { echo "$PROJECT_ROOT/docs/04_テスト設計/$(uc_slug).md"; }

# ═══════════════════════════════════════════════════════════════════════════════
# コマンド実装
# ═══════════════════════════════════════════════════════════════════════════════

# ── init ──────────────────────────────────────────────────────────────────────
cmd_init() {
  local usecase="${1:-}" aggregate="${2:-}"

  [[ -f "$CONFIG_FILE" ]] || die ".spec-runner/config.sh がありません。まず npx spec-runner を実行してください。"

  # 詳細設定がまだの場合は対話で設定（npx では開発環境だけ聞き、ここでパス・TDD 等を聞く）
  if [[ "${CONFIGURED:-false}" != "true" ]]; then
    echo ""
    info "詳細設定がまだです。パス・TDD 等を対話で設定します..."
    echo ""
    npx spec-runner --configure
    # 設定を再読み込み
    source "$CONFIG_FILE"
    echo ""
  fi

  # 引数なしの init ＝ 設定対話のみ。ユースケース名を渡すと作成に進む
  if [[ -z "$usecase" ]]; then
    info "設定が完了しました。最初のユースケースを開始するには:"
    echo ""
    echo "  ./.spec-runner/scripts/spec-runner.sh init \"ユースケース名\" \"集約名\""
    echo ""
    return 0
  fi

  check_debt

  echo ""
  step "ユースケース初期化: $usecase"
  echo ""

  # 既存のstateがあれば警告
  if [[ -f "$STATE_FILE" ]]; then
    local current
    current=$(state_get "usecase")
    warn "作業中のユースケース '$current' があります"
    read -r -p "上書きしますか？ [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "中止しました"
  fi

  # ブランチ作成
  local slug branch agg_branch
  slug=$(echo "$usecase" | tr ' ' '-')
  branch="feature/uc-$slug"

  # デフォルトブランチを取得（main / master など）
  local default_branch
  default_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

  if [[ -n "$aggregate" ]]; then
    agg_branch="aggregate/$(echo "$aggregate" | tr ' ' '-')"
    step "集約ブランチを確認/作成: $agg_branch"
    if ! git show-ref --verify --quiet "refs/heads/$agg_branch"; then
      git checkout -b "$agg_branch" 2>/dev/null || git checkout -b "$agg_branch" "$default_branch"
      ok "集約ブランチ作成: $agg_branch"
    else
      git checkout "$agg_branch"
      ok "集約ブランチに切替: $agg_branch"
    fi
  fi

  step "ユースケースブランチを作成: $branch"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    die "ブランチ $branch は既に存在します"
  fi
  local base="${aggregate:+aggregate/$(echo "$aggregate" | tr ' ' '-')}"
  git checkout -b "$branch" "${base:-$default_branch}" 2>/dev/null || git checkout -b "$branch"
  ok "ブランチ作成: $branch"

  # ステート初期化
  state_init "$usecase" "$aggregate"

  # 要件定義ファイルをテンプレートから生成（templates/requirement/template.md を必須とする）
  local req_file tmpl
  req_file=$(uc_req)
  tmpl="$SPEC_RUNNER_DIR/templates/01_要件定義/ひな形.md"
  [[ -f "$tmpl" ]] || die "要件テンプレートがありません: $tmpl （npx spec-runner でセットアップしてください）"

  mkdir -p "$(dirname "$req_file")"
  if [[ ! -f "$req_file" ]]; then
    sed "s/{{USECASE}}/$usecase/g; s/{{DATE}}/$(date +%Y-%m-%d)/g" "$tmpl" > "$req_file"
    ok "要件定義ファイルを作成: $req_file"
  else
    warn "要件定義ファイルは既に存在します: $req_file"
  fi

  echo ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "次のステップ:"
  info "  1. $req_file を編集する"
  info "  2. チームに確認してもらう"
  info "  3. ./.spec-runner/scripts/spec-runner.sh review-pass $req_file"
  info "  4. ./.spec-runner/scripts/spec-runner.sh design-high"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── require ───────────────────────────────────────────────────────────────────
cmd_require() {
  require_state
  local phase
  phase=$(state_get "phase")
  [[ "$phase" == "require" ]] || die "現在のフェーズは '$phase' です。要件定義フェーズではありません"

  local req_file
  req_file=$(uc_req)
  info "要件定義ファイル: $req_file"
  info "編集後、チームに確認してもらい:"
  info "  ./.spec-runner/scripts/spec-runner.sh review-pass $req_file"
}

# ── design-high ───────────────────────────────────────────────────────────────
cmd_design_high() {
  require_state

  echo ""
  step "【ゲートチェック】概要設計フェーズに進む条件を確認します"
  echo ""

  local errors=0
  local req_file
  req_file=$(uc_req)

  check_file "$req_file" "要件定義ファイル" || ((errors++))
  check_status "$req_file" "approved" "要件定義のステータス" || ((errors++))
  check_gate "glossary_checked" "用語集.md の確認済み" || ((errors++))

  if [[ $errors -gt 0 ]]; then
    echo ""
    die "ゲートを通過できません。${errors}件の条件が未達です ↑"
  fi

  echo ""
  ok "ゲート通過！概要設計フェーズを開始します"
  state_set_str "phase" "design-high"
  state_push_history "design-high フェーズ開始"

  # 概要設計ファイルをテンプレートから生成
  local high_file usecase
  high_file=$(uc_high)
  usecase=$(state_get "usecase")
  mkdir -p "$(dirname "$high_file")"

  if [[ ! -f "$high_file" ]]; then
    cat > "$high_file" <<TMPL
---
title: $usecase 概要設計
status: draft
requirement: $(uc_req)
created: $(date +%Y-%m-%d)
updated: $(date +%Y-%m-%d)
---

# $usecase 概要設計

## ユースケース

### UC-01: $usecase

**アクター**:
**前提条件**:
**主要フロー**:
1.
**事後条件**:
**例外フロー**:

## ドメインモデルの洗い出し

<!-- 用語集.md の日本語名で書く -->

### エンティティ候補

| 名前（日本語） | 説明 | 属する集約 |
|-------------|------|----------|
| | | |

### 値オブジェクト候補

| 名前（日本語） | 説明 |
|-------------|------|
| | |

### ドメインイベント候補

| 名前（日本語） | いつ発生するか |
|-------------|-------------|
| | |

## 未決事項

- [ ]

## レビュー記録

| 日付 | レビュアー | 結果 |
|------|----------|------|
TMPL
    ok "概要設計ファイルを作成: $high_file"
  fi

  echo ""
  info "次のステップ:"
  info "  1. $high_file を編集する"
  info "  2. チームにレビューしてもらう"
  info "  3. ./.spec-runner/scripts/spec-runner.sh review-pass $high_file"
  info "  4. ./.spec-runner/scripts/spec-runner.sh design-detail domain"
}

# ── design-detail ─────────────────────────────────────────────────────────────
cmd_design_detail() {
  require_state
  local sub="${1:-}"
  local valid_subs="domain usecase table infra"

  if [[ -z "$sub" ]]; then
    # サブフェーズなしで呼んだ場合、現在の進捗を表示
    echo ""
    step "詳細設計フェーズの進捗"
    echo ""
    local usecase detail_dir
    usecase=$(state_get "usecase")
    detail_dir=$(uc_detail)

    local all_ok=true
    for s in domain usecase table infra; do
      local f="$detail_dir/$s.md"
      if [[ -f "$f" ]]; then
        local st
        st=$(doc_status "$f")
        if [[ "$st" == "reviewed" || "$st" == "approved" ]]; then
          ok "$s.md (status: $st)"
        else
          warn "$s.md (status: $st) ← レビュー未完了"
          all_ok=false
        fi
      else
        fail "$s.md 未作成"
        all_ok=false
      fi
    done

    echo ""
    if $all_ok; then
      info "全サブフェーズ完了。次: ./.spec-runner/scripts/spec-runner.sh test-design"
    else
      info "次のサブフェーズ: ./.spec-runner/scripts/spec-runner.sh design-detail <domain|usecase|table|infra>"
    fi
    return
  fi

  echo "$valid_subs" | grep -qw "$sub" || die "無効なサブフェーズ: $sub（domain / usecase / table / infra）"

  # ゲートチェック
  echo ""
  step "【ゲートチェック】詳細設計($sub)フェーズに進む条件を確認します"
  echo ""

  local errors=0
  local high_file
  high_file=$(uc_high)

  check_file "$high_file" "概要設計ファイル" || ((errors++))
  check_status "$high_file" "reviewed" "概要設計のステータス" || ((errors++))

  # サブフェーズ固有の依存チェック
  local detail_dir
  detail_dir=$(uc_detail)
  case "$sub" in
    usecase)
      check_file "$detail_dir/ドメイン.md" "ドメインモデル設計" || ((errors++))
      check_status "$detail_dir/ドメイン.md" "reviewed" "ドメインモデルのレビュー" || ((errors++))
      ;;
    table)
      check_file "$detail_dir/ドメイン.md" "ドメインモデル設計" || ((errors++))
      check_status "$detail_dir/ドメイン.md" "reviewed" "ドメインモデルのレビュー" || ((errors++))
      check_file "$detail_dir/ユースケース.md" "ユースケース設計" || ((errors++))
      check_status "$detail_dir/ユースケース.md" "reviewed" "ユースケース設計のレビュー" || ((errors++))
      ;;
    infra)
      check_file "$detail_dir/ドメイン.md" "ドメインモデル設計" || ((errors++))
      check_status "$detail_dir/ドメイン.md" "reviewed" "ドメインモデルのレビュー" || ((errors++))
      check_file "$detail_dir/ユースケース.md" "ユースケース設計" || ((errors++))
      check_status "$detail_dir/ユースケース.md" "reviewed" "ユースケース設計のレビュー" || ((errors++))
      check_file "$detail_dir/テーブル.md" "テーブル設計" || ((errors++))
      check_status "$detail_dir/テーブル.md" "reviewed" "テーブル設計のレビュー" || ((errors++))
      ;;
  esac

  if [[ $errors -gt 0 ]]; then
    echo ""
    die "ゲートを通過できません。${errors}件の条件が未達です ↑"
  fi

  echo ""
  ok "ゲート通過！詳細設計($sub)フェーズを開始します"
  state_set_str "phase" "design-detail-$sub"
  state_push_history "design-detail-$sub フェーズ開始"

  # サブ種別→日本語ファイル名（ドメイン駆動の用語をそのまま）
  local sub_ja
  case "$sub" in
    domain)  sub_ja="ドメイン" ;;
    usecase) sub_ja="ユースケース" ;;
    table)   sub_ja="テーブル" ;;
    infra)   sub_ja="インフラ" ;;
    *)       sub_ja="$sub" ;;
  esac

  # ファイルをテンプレートから生成
  local dest_file usecase
  usecase=$(state_get "usecase")
  dest_file="$detail_dir/${sub_ja}.md"
  mkdir -p "$detail_dir"

  local tmpl="$SPEC_RUNNER_DIR/templates/03_詳細設計/${sub_ja}.md"
  if [[ ! -f "$dest_file" ]]; then
    if [[ -f "$tmpl" ]]; then
      sed "s/{{USECASE}}/$usecase/g; s/{{DATE}}/$(date +%Y-%m-%d)/g" "$tmpl" > "$dest_file"
    else
      echo "---
title: $usecase $(case $sub in domain) echo "ドメインモデル設計";; usecase) echo "ユースケース設計";; table) echo "テーブル設計";; infra) echo "インフラ設計";; esac)
status: draft
created: $(date +%Y-%m-%d)
updated: $(date +%Y-%m-%d)
---

# $usecase $(case $sub in domain) echo "ドメインモデル設計";; usecase) echo "ユースケース設計";; table) echo "テーブル設計";; infra) echo "インフラ設計";; esac)
" > "$dest_file"
    fi
    ok "設計ファイルを作成: $dest_file"
  fi

  echo ""
  info "次のステップ:"
  info "  1. $dest_file を編集する"
  info "  2. チームにレビューしてもらう"
  info "  3. ./.spec-runner/scripts/spec-runner.sh review-pass $dest_file"
  case "$sub" in
    domain)  info "  4. ./.spec-runner/scripts/spec-runner.sh design-detail usecase" ;;
    usecase) info "  4. ./.spec-runner/scripts/spec-runner.sh design-detail table" ;;
    table)   info "  4. ./.spec-runner/scripts/spec-runner.sh design-detail infra" ;;
    infra)   info "  4. ./.spec-runner/scripts/spec-runner.sh test-design" ;;
  esac
}

# ── test-design ───────────────────────────────────────────────────────────────
cmd_test_design() {
  require_state

  echo ""
  step "【ゲートチェック】テスト設計フェーズに進む条件を確認します"
  echo ""

  local errors=0
  local detail_dir
  detail_dir=$(uc_detail)

  for sub_ja in ドメイン ユースケース テーブル インフラ; do
    check_file "$detail_dir/$sub_ja.md" "03_詳細設計/$sub_ja.md" || ((errors++))
    check_status "$detail_dir/$sub_ja.md" "reviewed" "03_詳細設計/$sub_ja.md のレビュー" || ((errors++))
  done

  # 設計判断記録チェック（ADR が 1 件もない場合に促す）
  local adr_count
  adr_count=$(find "$PROJECT_ROOT/docs/99_設計判断記録" -name "*.md" ! -name "ひな形.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$adr_count" -eq 0 ]]; then
    warn "docs/99_設計判断記録/ にADRが1件もありません。設計判断があれば作成してください"
  fi

  if [[ $errors -gt 0 ]]; then
    echo ""
    die "ゲートを通過できません。${errors}件の条件が未達です ↑"
  fi

  echo ""
  ok "ゲート通過！テスト設計フェーズを開始します"
  state_set_str "phase" "test-design"
  state_push_history "test-design フェーズ開始"

  local test_file usecase
  usecase=$(state_get "usecase")
  test_file=$(uc_test)
  mkdir -p "$(dirname "$test_file")"

  if [[ ! -f "$test_file" ]]; then
    cat > "$test_file" <<TMPL
---
title: $usecase テスト設計
status: draft
created: $(date +%Y-%m-%d)
updated: $(date +%Y-%m-%d)
---

# $usecase テスト設計

## テスト方針

| 種別 | 対象 | ツール |
|------|------|-------|
| Unit | ドメインモデルの振る舞い | PHPUnit |
| Unit | 値オブジェクトのバリデーション | PHPUnit |
| Integration | ユースケース | PHPUnit + DB |
| Feature | APIエンドポイント | PHPUnit + HTTP |

## ドメインモデル テストケース

| # | テストケース名（日本語） | 入力 | 期待結果 | 種別 |
|---|----------------------|------|---------|------|
| 1 | の場合、となる | | | 正常 |

## ユースケース テストケース

| # | テストケース名（日本語） | 前提条件 | 入力 | 期待結果 |
|---|----------------------|---------|------|---------|
| 1 | | | | |

## テストコードチェックリスト

- [ ] ドメインモデルのUnitテスト作成済み（Red状態確認）
- [ ] 値オブジェクトのUnitテスト作成済み（Red状態確認）
- [ ] ユースケースのIntegrationテスト作成済み（Red状態確認）
- [ ] APIのFeatureテスト作成済み（Red状態確認）
TMPL
    ok "テスト設計ファイルを作成: $test_file"
  fi

  echo ""
  info "次のステップ:"
  info "  1. $test_file を編集する（テスト設計）"
  info "  2. テストコードを書く（実装前。Red状態でOK）"
  info "  3. git commit でテストコードをコミット"
  info "  4. ./.spec-runner/scripts/spec-runner.sh review-pass $test_file"
  info "  5. ./.spec-runner/scripts/spec-runner.sh implement"
}

# ── implement ─────────────────────────────────────────────────────────────────
cmd_implement() {
  require_state

  echo ""
  step "【ゲートチェック】実装フェーズに進む条件を確認します"
  echo ""

  local errors=0
  local test_file
  test_file=$(uc_test)

  # TDD 有効時のみ: テスト設計＋テストコードを必須（.spec-runner/config.sh の TDD_ENABLED=false で無効化可）
  if [[ "${TDD_ENABLED:-true}" != "false" ]]; then
    check_file "$test_file" "テスト設計ファイル" || ((errors++))
    check_status "$test_file" "reviewed" "テスト設計のレビュー" || ((errors++))

    local test_committed
    test_committed=$(state_get "gates.test_code_committed")
    if [[ "$test_committed" != "true" ]]; then
      # テストディレクトリ（.spec-runner/config.sh の TEST_DIR）配下の未コミットを検出
      local test_dir_prefix="${TEST_DIR:-tests}"
      local uncommitted_under_test
      uncommitted_under_test=$(git status --porcelain 2>/dev/null | awk '{print $2}' | grep -E "^${test_dir_prefix}/" | wc -l | tr -d ' ')
      if [[ "${uncommitted_under_test:-0}" -gt 0 ]]; then
        fail "テストコードが未コミットです（TDD 必須。${test_dir_prefix}/ 配下をコミットするか set-gate test_code_committed）"
        ((errors++))
      else
        warn "テストコードがコミット済みか未確認です"
        warn "確認後: ./.spec-runner/scripts/spec-runner.sh set-gate test_code_committed"
      fi
    else
      check_gate "test_code_committed" "テストコードのコミット確認" || ((errors++))
    fi
  else
    # TDD オプション時: テスト設計・テストコードは必須ではない（あれば推奨）
    if [[ -f "$test_file" ]]; then
      ok "テスト設計ファイル: $test_file（TDD オプションのため未レビューでも可）"
    else
      warn "テスト設計ファイルがありません（TDD オプションのため実装は進められます）"
    fi
  fi

  if [[ $errors -gt 0 ]]; then
    echo ""
    die "ゲートを通過できません。${errors}件の条件が未達です ↑"
  fi

  echo ""
  ok "ゲート通過！実装フェーズを開始します"
  state_set_str "phase" "implement"
  state_push_history "implement フェーズ開始"

  echo ""
  warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  warn " 実装フェーズのルール"
  warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info " 1. テストを Green にする実装を書く"
  info " 2. 設計と乖離した場合は先にドキュメントを更新する"
  info " 3. コードとドキュメントを同一コミットに含める"
  info " 4. 完了後: ./.spec-runner/scripts/spec-runner.sh complete"
  warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── complete ──────────────────────────────────────────────────────────────────
cmd_complete() {
  require_state

  echo ""
  step "【完了チェック】実装の完了条件を確認します"
  echo ""

  local errors=0

  # テストが通るか確認を促す
  warn "テストが全て通過していることを確認してください"
  read -r -p "全テスト通過済みですか？ [y/N] " ans_test
  [[ "$ans_test" =~ ^[Yy]$ ]] || { fail "テストを通過させてから完了してください"; ((errors++)); }

  # ドキュメントと実装の乖離チェック
  read -r -p "設計ドキュメントと実装に乖離はないですか？ [y/N] " ans_doc
  [[ "$ans_doc" =~ ^[Yy]$ ]] || { fail "ドキュメントを更新してから完了してください"; ((errors++)); }

  if [[ $errors -gt 0 ]]; then
    echo ""
    die "完了条件を満たしていません"
  fi

  state_set_str "phase" "complete"
  state_push_history "実装完了"

  # ブランチ情報の表示
  local branch agg_branch usecase
  branch=$(state_get "branch")
  agg_branch=$(state_get "aggregate_branch")
  usecase=$(state_get "usecase")

  echo ""
  ok "『$usecase』の実装が完了しました！"
  echo ""
  info "次のステップ:"
  info "  1. git push origin $branch"
  if [[ -f "$PROJECT_ROOT/.github/PULL_REQUEST_TEMPLATE.md" ]]; then
    info "  2. Pull Request を作成（.github/PULL_REQUEST_TEMPLATE.md を使用）"
  else
    info "  2. Pull Request を作成"
  fi
  if [[ -n "$agg_branch" ]]; then
    info "  3. PRマージ先: $agg_branch"
    info "  4. 関連ユースケースがすべて揃ったら $agg_branch → main へPR"
  fi
}

# ── review-pass ───────────────────────────────────────────────────────────────
cmd_review_pass() {
  local file="${1:-}"
  [[ -n "$file" ]] || die "使い方: ./.spec-runner/scripts/spec-runner.sh review-pass <ファイルパス>"
  [[ -f "$file" ]] || die "ファイルが存在しません: $file"

  # frontmatterのstatusを更新
  local today
  today=$(date +%Y-%m-%d)

  if grep -q '^status:' "$file"; then
    # 既存のstatusを更新（同一デバイス上に一時ファイルを作成してmv）
    local tmp
    tmp="${file}.tmp.$$"
    sed "s/^status: .*/status: reviewed/" "$file" > "$tmp" && mv "$tmp" "$file"
    # updated日付も更新
    tmp="${file}.tmp.$$"
    sed "s/^updated: .*/updated: $today/" "$file" > "$tmp" && mv "$tmp" "$file"
  else
    die "ファイルにfrontmatter(status:)がありません: $file"
  fi

  ok "レビュー通過: $file (status: reviewed)"

  # どのゲートフラグを立てるか判定
  require_state
  local uc_slug_val
  uc_slug_val=$(uc_slug)

  case "$file" in
    *01_要件*)
      state_set_bool "gates.require_approved" true
      state_set_str "phase" "require-approved"
      # statusもapprovedに（同一デバイス上で一時ファイル）
      local tmp2
      tmp2="${file}.tmp.$$"
      sed "s/^status: .*/status: approved/" "$file" > "$tmp2" && mv "$tmp2" "$file"
      ok "ゲート更新: require_approved = true"
      info "次: docs/03_用語集.md を確認後 ./.spec-runner/scripts/spec-runner.sh set-gate glossary_checked"
      info "    ./.spec-runner/scripts/spec-runner.sh design-high"
      ;;
    *02_概要設計*)
      state_set_bool "gates.high_level_reviewed" true
      ok "ゲート更新: high_level_reviewed = true"
      info "次: ./.spec-runner/scripts/spec-runner.sh design-detail domain"
      ;;
    *ドメイン*)
      state_set_bool "gates.domain_model_reviewed" true
      ok "ゲート更新: domain_model_reviewed = true"
      info "次: ./.spec-runner/scripts/spec-runner.sh design-detail usecase"
      ;;
    *ユースケース*)
      state_set_bool "gates.usecase_design_reviewed" true
      ok "ゲート更新: usecase_design_reviewed = true"
      info "次: ./.spec-runner/scripts/spec-runner.sh design-detail table"
      ;;
    *テーブル*)
      state_set_bool "gates.table_design_reviewed" true
      ok "ゲート更新: table_design_reviewed = true"
      info "次: ./.spec-runner/scripts/spec-runner.sh design-detail infra"
      ;;
    *インフラ*)
      state_set_bool "gates.infra_design_reviewed" true
      ok "ゲート更新: infra_design_reviewed = true"
      info "次: ./.spec-runner/scripts/spec-runner.sh test-design"
      ;;
    *04_テスト設計*)
      state_set_bool "gates.test_design_reviewed" true
      ok "ゲート更新: test_design_reviewed = true"
      info "テストコードをコミット後: ./.spec-runner/scripts/spec-runner.sh set-gate test_code_committed"
      info "その後: ./.spec-runner/scripts/spec-runner.sh implement"
      ;;
  esac
}

# ── set-gate ──────────────────────────────────────────────────────────────────
cmd_set_gate() {
  require_state
  local gate="${1:-}"
  [[ -n "$gate" ]] || die "使い方: ./.spec-runner/scripts/spec-runner.sh set-gate <ゲート名>"
  state_set_bool "gates.$gate" true
  ok "ゲートフラグ設定: $gate = true"
}

# ── status 表示用：フェーズ・ゲートの日本語ラベル ─────────────────────────────
phase_ja() {
  case "$1" in
    require) echo "要件定義" ;;
    require-approved) echo "要件承認済み" ;;
    design-high) echo "概要設計" ;;
    design-detail*) echo "詳細設計" ;;
    test-design) echo "テスト設計" ;;
    implement) echo "実装" ;;
    complete) echo "完了" ;;
    fix) echo "修正" ;;
    *) echo "$1" ;;
  esac
}
gate_ja() {
  case "$1" in
    require_approved) echo "要件レビュー済み" ;;
    glossary_checked) echo "用語集確認済み" ;;
    high_level_reviewed) echo "概要設計レビュー済み" ;;
    domain_model_reviewed) echo "ドメインモデルレビュー済み" ;;
    usecase_design_reviewed) echo "ユースケース設計レビュー済み" ;;
    table_design_reviewed) echo "テーブル設計レビュー済み" ;;
    infra_design_reviewed) echo "インフラ設計レビュー済み" ;;
    test_design_reviewed) echo "テスト設計レビュー済み" ;;
    test_code_committed) echo "テストコードコミット済み" ;;
    *) echo "$1" ;;
  esac
}

# ── status: プロジェクト土台（憲章・仕様）の未記入チェック ─────────────────────
# プレースホルダーが残っている＝テンプレートのまま＝未記入とみなす
CONSTITUTION_PLACEHOLDER="この節を編集"
SPECIFY_PLACEHOLDER="（1〜2文で。例:"

is_foundation_written() {
  local kind="$1"
  case "$kind" in
    constitution)
      [[ -f "$PROJECT_ROOT/docs/01_憲章.md" ]] && ! grep -q "$CONSTITUTION_PLACEHOLDER" "$PROJECT_ROOT/docs/01_憲章.md" 2>/dev/null
      ;;
    specify)
      [[ -f "$PROJECT_ROOT/docs/02_仕様.md" ]] && ! grep -q "$SPECIFY_PLACEHOLDER" "$PROJECT_ROOT/docs/02_仕様.md" 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

# 憲章・仕様の未記入案内を表示。mode: no_state（ユースケースなし） or has_state（開始済み）
status_show_foundation_reminder() {
  local mode="${1:-no_state}"
  local c_ok s_ok
  is_foundation_written constitution && c_ok=1 || c_ok=0
  is_foundation_written specify && s_ok=1 || s_ok=0
  [[ $c_ok -eq 1 && $s_ok -eq 1 ]] && return

  if [[ "$mode" == "no_state" ]]; then
    info "プロジェクトの土台（init の前推奨）:"
    [[ $c_ok -eq 0 ]] && info "  ✗ 憲章がまだ記入されていません → docs/01_憲章.md （/sr-憲章 で編集）"
    [[ $s_ok -eq 0 ]] && info "  ✗ 仕様がまだ記入されていません   → docs/02_仕様.md （/sr-仕様 で編集）"
  else
    info "💡 プロジェクトの土台:"
    [[ $c_ok -eq 0 ]] && info "  憲章がまだ → /sr-憲章"
    [[ $s_ok -eq 0 ]] && info "  仕様がまだ → /sr-仕様"
  fi
  info ""
}

# ── status ─────────────────────────────────────────────────────────────────────
cmd_status() {
  if [[ ! -f "$STATE_FILE" ]]; then
    info "作業中のユースケースはありません"
    info ""
    status_show_foundation_reminder no_state
    info "開始するには: チャットで /sr-初期化 <ユースケース名> またはターミナルで下記を実行してください。"
    info "  例（チャット）: /sr-初期化 会員登録 会員"
    info "  例（ターミナル）: ./.spec-runner/scripts/spec-runner.sh init 会員登録 会員"
    return
  fi

  status_show_foundation_reminder has_state

  local usecase phase branch agg_branch
  usecase=$(state_get "usecase")
  phase=$(state_get "phase")
  branch=$(state_get "branch")
  agg_branch=$(state_get "aggregate_branch")

  local phase_ja_label
  phase_ja_label=$(phase_ja "$phase")

  echo ""
  echo -e "${BOLD}════════════════════════════════════════${NC}"
  echo -e "${BOLD} 現在の作業状況${NC}"
  echo -e "${BOLD}════════════════════════════════════════${NC}"
  echo -e "  ユースケース : ${CYAN}$usecase${NC}"
  echo -e "  フェーズ    : ${YELLOW}$phase_ja_label${NC}"
  echo -e "  ブランチ    : ${BLUE}$branch${NC}"
  [[ -n "$agg_branch" ]] && echo -e "  集約ブランチ: ${BLUE}$agg_branch${NC}"
  echo ""
  echo -e "${BOLD} ゲート状況${NC}"

  local gates
  for gate in require_approved glossary_checked high_level_reviewed \
              domain_model_reviewed usecase_design_reviewed \
              table_design_reviewed infra_design_reviewed \
              test_design_reviewed test_code_committed; do
    local val gate_label
    val=$(state_get "gates.$gate")
    gate_label=$(gate_ja "$gate")
    if [[ "$val" == "true" ]]; then
      echo -e "  ${GREEN}✓${NC} $gate_label"
    else
      echo -e "  ${RED}✗${NC} $gate_label"
    fi
  done

  echo ""
  echo -e "${BOLD} 次にやるべきこと${NC} ${CYAN}（チャットでは /sr-* スラッシュコマンドが使えます）${NC}"
  local req_file high_file
  req_file=$(uc_req)
  high_file=$(uc_high)
  case "$phase" in
    require)
      echo -e "  1. ${CYAN}$req_file${NC} を編集"
      echo -e "  2. /sr-レビュー $req_file"
      echo -e "  3. /sr-ゲート設定 glossary_checked"
      echo -e "  4. /sr-概要設計"
      ;;
    design-high)
      echo -e "  1. ${CYAN}$high_file${NC} を編集"
      echo -e "  2. /sr-レビュー $high_file"
      echo -e "  3. /sr-詳細設計 domain"
      ;;
    design-detail*)
      if [[ "$(state_get "gates.domain_model_reviewed")" != "true" ]]; then
        echo -e "  1. docs/03_詳細設計/$(uc_slug)/ドメイン.md を編集"
        echo -e "  2. /sr-レビュー のあと /sr-詳細設計 usecase"
      elif [[ "$(state_get "gates.usecase_design_reviewed")" != "true" ]]; then
        echo -e "  1. docs/03_詳細設計/$(uc_slug)/ユースケース.md を編集"
        echo -e "  2. /sr-レビュー のあと /sr-詳細設計 table"
      elif [[ "$(state_get "gates.table_design_reviewed")" != "true" ]]; then
        echo -e "  1. docs/03_詳細設計/$(uc_slug)/テーブル.md を編集"
        echo -e "  2. /sr-レビュー のあと /sr-詳細設計 infra"
      elif [[ "$(state_get "gates.infra_design_reviewed")" != "true" ]]; then
        echo -e "  1. docs/03_詳細設計/$(uc_slug)/インフラ.md を編集"
        echo -e "  2. /sr-レビュー のあと /sr-テスト設計"
      else
        echo -e "  /sr-テスト設計"
      fi
      ;;
    test-design)
      echo -e "  1. docs/04_テスト設計/$(uc_slug).md を編集し、テストコードを書く（Red）"
      echo -e "  2. テストコードをコミット → /sr-ゲート設定 test_code_committed"
      echo -e "  3. /sr-レビュー docs/04_テスト設計/$(uc_slug).md"
      echo -e "  4. /sr-実装"
      ;;
    implement)
      echo -e "  実装してテストを Green にしたら: /sr-完了"
      ;;
    complete)
      echo -e "  完了。PR を作成してマージしてください。"
      ;;
    fix)
      echo -e "  案内に従って該当ドキュメントを修正し、必要なら /sr-詳細設計 等から再実行。"
      ;;
    *)
      echo -e "  ./.spec-runner/scripts/spec-runner.sh help でコマンド一覧を確認"
      ;;
  esac
  echo ""
  echo -e "${BOLD} 履歴${NC}"
  jq -r '.history[]' "$STATE_FILE" 2>/dev/null | tail -5 | while read -r line; do
    echo "  $line"
  done
  echo -e "${BOLD}════════════════════════════════════════${NC}"

  # debt確認
  if [[ -f "$DEBT_FILE" ]]; then
    local unchecked
    unchecked=$(grep -c '^\- \[ \]' "$DEBT_FILE" 2>/dev/null; true)
    unchecked="${unchecked:-0}"
    if [[ "${unchecked}" -gt 0 ]]; then
      warn "ドキュメント負債: ${unchecked} 件"
    fi
  fi
}

# ── fix ───────────────────────────────────────────────────────────────────────
cmd_fix() {
  local content="${1:-}"
  [[ -n "$content" ]] || die "使い方: ./.spec-runner/scripts/spec-runner.sh fix <修正内容>"

  echo ""
  step "修正フロー: $content"
  echo ""
  echo "修正レベルを選択してください:"
  echo "  1) ドメインモデルの構造変更 → domain設計から再実行"
  echo "  2) ユースケースのフロー変更 → usecase設計から再実行"
  echo "  3) APIの仕様変更           → infra設計から再実行"
  echo "  4) テーブル構造の変更      → table設計から再実行"
  echo "  5) バグ修正（設計は正しい）→ テスト追加→実装修正"
  echo ""
  read -r -p "番号を選択 [1-5]: " level

  local usecase slug branch
  slug=$(echo "$content" | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-30)
  usecase="${2:-$(state_get "usecase" 2>/dev/null || echo "unknown")}"
  branch="fix/$(echo "$usecase" | tr ' ' '-')-$slug"

  git checkout -b "$branch" 2>/dev/null || warn "ブランチ作成に失敗しました（手動で作成してください）"

  case "$level" in
    1)
      info "ドメインモデルから再設計します"
      info "修正ファイル:"
      info "  docs/03_詳細設計/$(uc_slug)/ドメイン.md → status: draft に戻す"
      info "  docs/03_詳細設計/$(uc_slug)/ユースケース.md → 再確認"
      info "  docs/04_テスト設計/$(uc_slug).md → 再確認"
      ;;
    2)
      info "ユースケース設計から修正します"
      info "  docs/03_詳細設計/$(uc_slug)/ユースケース.md → status: draft に戻す"
      info "  docs/04_テスト設計/$(uc_slug).md → 再確認"
      ;;
    3)
      info "インフラ設計から修正します"
      info "  docs/03_詳細設計/$(uc_slug)/インフラ.md → status: draft に戻す"
      ;;
    4)
      info "テーブル設計から修正します"
      info "  docs/03_詳細設計/$(uc_slug)/テーブル.md → status: draft に戻す"
      ;;
    5)
      info "テストを追加して実装を修正します"
      info "  テストコード追加 → git commit → ./.spec-runner/scripts/spec-runner.sh implement"
      ;;
    *)
      die "無効な選択です"
      ;;
  esac

  state_set_str "phase" "fix"
  state_push_history "修正開始: $content (level: $level)"
}

# ── hotfix ────────────────────────────────────────────────────────────────────
cmd_hotfix() {
  local content="${1:-}"
  [[ -n "$content" ]] || die "使い方: ./.spec-runner/scripts/spec-runner.sh hotfix <内容>"

  local slug branch
  slug=$(echo "$content" | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-30)
  branch="hotfix/$slug"

  step "緊急修正ブランチを作成: $branch"
  git checkout -b "$branch" main

  ok "ブランチ作成: $branch"
  warn "緊急修正後、ドキュメント負債として記録されます"

  # debt.mdに追記
  mkdir -p "$(dirname "$DEBT_FILE")"
  [[ -f "$DEBT_FILE" ]] || echo "# ドキュメント負債" > "$DEBT_FILE"

  cat >> "$DEBT_FILE" <<DEBT

## $(date +%Y-%m-%d): hotfix/$slug

- [ ] 修正内容に対応するテスト設計ドキュメントの更新
  - hotfix内容: $content
  - 対象ユースケース: 要確認
  - 修正したコード: 要確認
DEBT

  ok "負債を記録: $DEBT_FILE"
  info "修正完了後: git push origin $branch → main へPR"
  info "次回の init 時に負債の消化を促されます"
}

# ── メインルーター ────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    init)          cmd_init "$@" ;;
    require)       cmd_require "$@" ;;
    design-high)   cmd_design_high "$@" ;;
    design-detail) cmd_design_detail "$@" ;;
    test-design)   cmd_test_design "$@" ;;
    implement)     cmd_implement "$@" ;;
    complete)      cmd_complete "$@" ;;
    review-pass)   cmd_review_pass "$@" ;;
    set-gate)      cmd_set_gate "$@" ;;
    status)        cmd_status "$@" ;;
    fix)           cmd_fix "$@" ;;
    hotfix)        cmd_hotfix "$@" ;;
    help|--help|-h)
      echo ""
      echo -e "${BOLD}使い方:${NC}"
      echo "  ./.spec-runner/scripts/spec-runner.sh <コマンド> [引数]"
      echo ""
      echo -e "${BOLD}新規開発フロー:${NC}"
      echo "  init [ユースケース名] [集約名]  引数なしで設定対話。名前を渡すとユースケース作成"
      echo "  require                        要件定義フェーズ（ファイルパスを確認）"
      echo "  design-high                    概要設計フェーズに移行（ゲートチェック）"
      echo "  design-detail <sub>            詳細設計フェーズ（sub: domain|usecase|table|infra）"
      echo "  test-design                    テスト設計フェーズに移行（ゲートチェック）"
      echo "  implement                      実装フェーズに移行（ゲートチェック）"
      echo "  complete                       実装完了（完了チェック）"
      echo ""
      echo -e "${BOLD}レビュー:${NC}"
      echo "  review-pass <ファイル>         ドキュメントをレビュー通過にする"
      echo "  set-gate <ゲート名>            手動でゲートフラグを立てる"
      echo ""
      echo -e "${BOLD}確認:${NC}"
      echo "  status                         現在の状態を表示"
      echo ""
      echo -e "${BOLD}修正フロー:${NC}"
      echo "  fix <修正内容>                 通常修正フロー（影響範囲分析）"
      echo "  hotfix <内容>                  緊急修正（負債として記録）"
      echo ""
      ;;
    *)
      die "不明なコマンド: $cmd\n使い方: ./.spec-runner/scripts/spec-runner.sh help"
      ;;
  esac
}

main "$@"
