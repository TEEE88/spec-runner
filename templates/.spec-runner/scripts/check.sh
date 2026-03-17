#!/usr/bin/env bash
# 確認の一括実行。引数なしで「健全性 → ドリフト」を順に実行（1 コマンドで両方）。必要なら個別に。
# 使用: .spec-runner/scripts/check.sh [--健全性のみ|--ドリフトのみ]
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  --健全性のみ)
    exec "$DIR/check/health.sh" "${@:2}"
    ;;
  --ドリフトのみ)
    exec "$DIR/check/drift.sh" "${@:2}"
    ;;
  *)
    # 引数なし: 健全性 → ドリフト（用語・スキーマ・命名）を順に実行。どれか失敗で exit 1
    "$DIR/check/health.sh" && \
    "$DIR/check/drift.sh" --用語 && \
    "$DIR/check/drift.sh" --スキーマ && \
    "$DIR/check/drift.sh" --命名
    ;;
esac
