#!/usr/bin/env bash
# spec-runner エントリポイント。次のステップ（現在フェーズ・やるべきステップ .md）を返す。
# 使用: .spec-runner/spec-runner.sh [次のステップ] [--json|--lock]

set -e
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"
SR="$REPO_ROOT/.spec-runner/scripts"

cmd="${1:-}"
shift || true

case "$cmd" in
  次のステップ|"")
    if [[ "$cmd" == "" ]]; then
      # 引数なしは「次のステップ」として扱う（/spec-runner スラッシュコマンド用）
      :
    fi
    case "${1:-}" in
      --lock)   exec "$SR/spec-runner-core.sh" --status ;;
      *)        exec "$SR/spec-runner-core.sh" --phase "$@" ;;
    esac
    ;;
  *)
    echo "spec-runner: 引数なし、または「次のステップ」[--json|--lock] のみ対応しています。" >&2
    echo "  使用例: .spec-runner/spec-runner.sh 次のステップ --json" >&2
    exit 1
    ;;
esac
