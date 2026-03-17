#!/usr/bin/env bash
# プロジェクト初期設定を AI と対話しながら行う。設定は .spec-runner/project.json に集約する。
# 使用例: .spec-runner/scripts/setup/init-project.sh

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
SPEC_RUNNER="$REPO_ROOT/.spec-runner"
CONFIG="$SPEC_RUNNER/project.json"

command -v jq >/dev/null 2>&1 || { echo "init-project: jq が必要です（brew install jq）" >&2; exit 1; }

echo "=== spec-runner プロジェクト初期設定 ==="
echo ""

# --- 1. テストコマンド ---
detect_test_command() {
  if [[ -f "package.json" ]] && grep -q '"test"' package.json 2>/dev/null; then
    echo "npm test"
    return
  fi
  if [[ -f "pyproject.toml" ]]; then
    command -v poetry >/dev/null 2>&1 && echo "poetry run pytest" || echo "pytest"
    return
  fi
  if [[ -f "go.mod" ]]; then
    echo "go test ./..."
    return
  fi
  echo ""
}

CURRENT_TEST=""
[[ -f "$CONFIG" ]] && CURRENT_TEST=$(jq -r '.test_command.run // empty' "$CONFIG" 2>/dev/null)
[[ -z "$CURRENT_TEST" ]] && [[ -f "$SPEC_RUNNER/test-command.json" ]] && CURRENT_TEST=$(jq -r '.run // empty' "$SPEC_RUNNER/test-command.json" 2>/dev/null)
DETECTED=$(detect_test_command)

echo "【1】テストコマンド（require-tests-green.sh が実行するコマンド）"
if [[ -n "$CURRENT_TEST" ]]; then
  echo "  現在: $CURRENT_TEST"
fi
if [[ -n "$DETECTED" ]]; then
  echo "  検出候補: $DETECTED"
fi
echo "  (1) 検出したコマンドを使う  (2) 自分で入力  (Enter = 変更しない)"
read -r choice
case "$choice" in
  1)
    if [[ -n "$DETECTED" ]]; then
      RUN_CMD="$DETECTED"
    else
      echo "  検出できませんでした。コマンドを入力してください（例: npm test）:"
      read -r RUN_CMD
    fi
    ;;
  2)
    echo "  コマンドを入力（例: docker compose run --rm app npm test）:"
    read -r RUN_CMD
    ;;
  *)
    RUN_CMD="${CURRENT_TEST:-$DETECTED}"
    ;;
esac
echo ""

# --- 2. 命名規則 ---
echo "【2】命名規則（ブランチ・UC 仕様書・設計判断記録のファイル名）"
DEFAULT_BRANCH="feature"
DEFAULT_UC="UC-NNN-xxx.md"
DEFAULT_ADR="MMDD-題名.md"
if [[ -f "$CONFIG" ]]; then
  DEFAULT_BRANCH=$(jq -r '.naming.branch_prefix // "feature"' "$CONFIG" 2>/dev/null)
fi
echo "  ブランチ例: ${DEFAULT_BRANCH}/UC-001-create-task"
echo "  UC 仕様書例: docs/02_ユースケース仕様/<カテゴリ>/UC-001-create-task.md"
echo "  設計判断記録例: docs/04_アーキテクチャ/設計判断記録/0314-アーキテクチャ選定.md"
echo "  変更しますか？ (y/N)"
read -r change_naming
if [[ "$change_naming" == "y" || "$change_naming" == "Y" ]]; then
  echo "  ブランチ接頭辞（Enter = $DEFAULT_BRANCH）:"
  read -r bp
  BRANCH_PREFIX="${bp:-$DEFAULT_BRANCH}"
  echo "  → branch_prefix: $BRANCH_PREFIX（project.json に反映）"
else
  BRANCH_PREFIX="$DEFAULT_BRANCH"
fi
# UC 以外の作業用ブランチ接頭辞（feature/<接頭辞>/xxx）
DEFAULT_OTHER_WORK="work, infra, cicd"
if [[ -f "$CONFIG" ]]; then
  current_ow=$(jq -r '.naming.other_work_prefixes | join(", ") // empty' "$CONFIG" 2>/dev/null)
  [[ -n "$current_ow" ]] && DEFAULT_OTHER_WORK="$current_ow"
fi
echo "  UC 以外の作業用ブランチ接頭辞（カンマ区切り。例: feature/cicd/xxx, feature/infra/xxx）"
echo "  現在: [$DEFAULT_OTHER_WORK]"
echo "  変更する場合は入力、そのままなら Enter:"
read -r other_work_input
if [[ -n "$other_work_input" ]]; then
  OTHER_WORK_JSON=$(echo "$other_work_input" | jq -R 'split(",") | map(gsub("^ +| +$";"")) | map(select(length>0))')
  echo "  → other_work_prefixes を反映します"
else
  OTHER_WORK_JSON=""
fi
echo ""

# --- 3. 設計書チェック（必須ドキュメント）---
echo "【3】設計書チェック（ゲート確認で必須とするドキュメント一覧）"
CREATE_OR_UPDATE=""
if [[ -f "$CONFIG" ]]; then
  echo "  現在の project.json の required_docs を使用します。"
  # naming.branch_prefix / other_work_prefixes / test_command.run を今回の値で更新
  jq --arg bp "$BRANCH_PREFIX" '.naming.branch_prefix = $bp' "$CONFIG" > "${CONFIG}.tmp" 2>/dev/null && mv "${CONFIG}.tmp" "$CONFIG"
  if [[ -n "$OTHER_WORK_JSON" ]]; then
    jq --argjson ow "$OTHER_WORK_JSON" '.naming.other_work_prefixes = $ow' "$CONFIG" > "${CONFIG}.tmp" 2>/dev/null && mv "${CONFIG}.tmp" "$CONFIG"
  fi
  if [[ -n "$RUN_CMD" ]]; then
    jq --arg run "$RUN_CMD" '.test_command = {run: $run}' "$CONFIG" > "${CONFIG}.tmp" 2>/dev/null && mv "${CONFIG}.tmp" "$CONFIG"
    echo "  → test_command と naming を反映しました: $RUN_CMD"
  else
    echo "  命名（branch_prefix / other_work_prefixes）を反映しました。編集は .spec-runner/project.json を直接変更してください。"
  fi
else
  echo "  project.json がありません。デフォルトの必須ドキュメントで作成しますか？ (Y/n)"
  read -r create_docs
  if [[ "$create_docs" != "n" && "$create_docs" != "N" ]]; then
    CREATE_OR_UPDATE=1
    mkdir -p "$SPEC_RUNNER"
    if [[ -f "$SPEC_RUNNER/project.json.example" ]]; then
      cp "$SPEC_RUNNER/project.json.example" "$CONFIG"
      jq --arg bp "$BRANCH_PREFIX" '.naming.branch_prefix = $bp' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
      [[ -n "$OTHER_WORK_JSON" ]] && jq --argjson ow "$OTHER_WORK_JSON" '.naming.other_work_prefixes = $ow' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
      if [[ -n "$RUN_CMD" ]]; then
        jq --arg run "$RUN_CMD" '.test_command = {run: $run}' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
      fi
      echo "  → project.json をデフォルトで作成しました。"
    else
      ow_default='["work","infra","cicd"]'
      [[ -n "$OTHER_WORK_JSON" ]] && ow_default="$OTHER_WORK_JSON"
      jq -n \
        --arg bp "$BRANCH_PREFIX" \
        --arg run "${RUN_CMD:-npm test}" \
        --argjson ow "$ow_default" \
        '{naming: {branch_prefix: $bp, uc_id_pattern: "UC-[0-9]{3}", uc_spec_basename: "{uc_id}-{slug}.md", adr_basename: "MMDD-{title}.md", docs_05_categories: true, other_work_prefixes: $ow}, required_docs: {charter: ["docs/01_憲章/憲章.md"], domain: ["docs/03_ドメイン設計/ユビキタス言語辞書.md", "docs/03_ドメイン設計/ドメインモデル.md", "docs/03_ドメイン設計/集約.md"], architecture: ["docs/04_アーキテクチャ/パターン選定.md", "docs/04_アーキテクチャ/インフラ方針.md", "docs/04_アーキテクチャ/設計判断記録"], grade_a: ["docs/05_インフラ設計/schema.dbml"], gate3_openapi: ["docs/06_API仕様/openapi.yaml"]}, test_design: {dir: "tests", pattern: "*.spec.*"}, test_command: {run: $run}}' \
        > "$CONFIG"
      echo "  → project.json を作成しました。"
    fi
  fi
fi
echo ""

echo "=== 初期設定の流れは以上です ==="
echo "  再実行: .spec-runner/scripts/setup/init-project.sh"
echo "  設定の編集: .spec-runner/project.json（1 ファイルに集約）"
