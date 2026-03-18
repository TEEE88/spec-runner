#!/usr/bin/env bash
# テストコマンドを実行し、すべてグリーンでないと終了コード 1 を返す。
# コマンドは .spec-runner/project.json の test_command.run のみ（必須）。

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
SPEC_RUNNER="${REPO_ROOT}/.spec-runner"
PROJECT_JSON="${SPEC_RUNNER}/project.json"
command -v jq >/dev/null 2>&1 || { echo "require-tests-green: jq が必要です（brew install jq）" >&2; exit 1; }
[[ -f "$PROJECT_JSON" ]] || { echo "require-tests-green: $PROJECT_JSON がありません" >&2; exit 1; }

RUN_CMD=$(jq -r '.test_command.run' "$PROJECT_JSON")
[[ -n "$RUN_CMD" && "$RUN_CMD" != "null" ]] || {
  echo "require-tests-green: project.json に test_command.run を設定してください。" >&2
  exit 1
}

echo "require-tests-green: テストを実行しています（$RUN_CMD）..."
if eval "$RUN_CMD"; then
  echo "require-tests-green: すべてグリーンです。実装完了の条件（テスト）を満たしています。"
  exit 0
else
  echo "" >&2
  echo "require-tests-green: テストが失敗しました。実装完了とみなせません。" >&2
  exit 1
fi
