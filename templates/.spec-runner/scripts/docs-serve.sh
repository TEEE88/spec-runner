#!/usr/bin/env bash
# MkDocs + Material で docs/ をプレビュー（プロジェクトルートで実行される想定）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DOCS_PORT="${DOCS_PORT:-8000}"
REQ="requirements-docs.txt"

if [[ ! -f "$REQ" ]]; then
  echo "ERROR: ${REQ} が見つかりません。npx spec-runner を実行して MkDocs 用ファイルを展開してください。" >&2
  exit 1
fi

if [[ ! -d .venv-docs ]]; then
  python3 -m venv .venv-docs
fi

./.venv-docs/bin/pip install -q -r "$REQ"
exec ./.venv-docs/bin/mkdocs serve --dev-addr "127.0.0.1:${DOCS_PORT}"
