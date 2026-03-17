#!/usr/bin/env bash
# テストコマンドを実行し、すべてグリーンでないと終了コード 1 を返す。
# 実装ステップの「完了検証」で必須。コマンドは .spec-runner/project.json の test_command.run で指定。
# 未設定時はプロジェクトを検出して候補を実行し、設定を促す。

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
SPEC_RUNNER="${REPO_ROOT}/.spec-runner"
PROJECT_JSON="${SPEC_RUNNER}/project.json"
LEGACY_TEST_JSON="${SPEC_RUNNER}/test-command.json"

# 設定を読む: project.json の test_command.run → 後方互換で test-command.json の run
get_run_command() {
  local run=""
  if [[ -f "$PROJECT_JSON" ]]; then
    if command -v jq >/dev/null 2>&1; then
      run=$(jq -r '.test_command.run // empty' "$PROJECT_JSON" 2>/dev/null)
    else
      run=$(grep -o '"run"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_JSON" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)" *$/\1/')
    fi
  fi
  if [[ -z "$run" ]] && [[ -f "$LEGACY_TEST_JSON" ]]; then
    if command -v jq >/dev/null 2>&1; then
      run=$(jq -r '.run // empty' "$LEGACY_TEST_JSON" 2>/dev/null)
    else
      run=$(grep -o '"run"[[:space:]]*:[[:space:]]*"[^"]*"' "$LEGACY_TEST_JSON" 2>/dev/null | sed 's/.*"\([^"]*\)" *$/\1/')
    fi
  fi
  echo -n "$run"
}

# 未設定時に検出して実行するコマンドを決める
detect_and_run() {
  if [[ -f "package.json" ]] && grep -q '"test"' package.json 2>/dev/null; then
    echo "npm test"
    return
  fi
  if [[ -f "pyproject.toml" ]]; then
    if command -v poetry >/dev/null 2>&1; then
      echo "poetry run pytest"
    else
      echo "pytest"
    fi
    return
  fi
  if [[ -f "go.mod" ]]; then
    echo "go test ./..."
    return
  fi
  if [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
    # サービス名は app を仮定（未設定時は検出のみで実行しない）
    echo ""
    return
  fi
  echo ""
}

RUN_CMD=$(get_run_command)

# 未設定なら検出
if [[ -z "$RUN_CMD" ]]; then
  RUN_CMD=$(detect_and_run)
  if [[ -z "$RUN_CMD" ]]; then
    echo "require-tests-green: テストコマンドが未設定です。.spec-runner/project.json の test_command.run を設定するか、初期化（init-project.sh）を実行してください。" >&2
    echo "  例: project.json に \"test_command\": {\"run\": \"npm test\"} を追加" >&2
    exit 1
  fi
  echo "require-tests-green: project.json に test_command がありません。検出したコマンドで実行します: $RUN_CMD" >&2
  echo "  恒久設定: 初期化で設定するか、project.json に test_command.run を追加してください。" >&2
fi

echo "require-tests-green: テストを実行しています（$RUN_CMD）..."
if eval "$RUN_CMD"; then
  echo "require-tests-green: すべてグリーンです。実装完了の条件（テスト）を満たしています。"
  exit 0
else
  echo "" >&2
  echo "require-tests-green: テストが失敗しました。実装完了とみなせません。" >&2
  echo "  テストを修正し、再度 .spec-runner/scripts/test/require-tests-green.sh を実行してください。" >&2
  echo "  コマンドを変更する場合は .spec-runner/project.json の test_command.run を編集するか、初期化（init-project.sh）を実行してください。" >&2
  exit 1
fi
