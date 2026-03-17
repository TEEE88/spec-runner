#!/usr/bin/env bash
# docs/02_ユースケース仕様/<カテゴリ>/UC-*.md から次に使う UC-NNN を表示する（例: UC-001）

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
DIR="$REPO_ROOT/docs/02_ユースケース仕様"
mkdir -p "$DIR"
MAX=0
for f in "$DIR"/*/UC-*.md; do
  [[ -e "$f" ]] || continue
  base=$(basename "$f" .md)
  if [[ "$base" =~ ^UC-([0-9]{3})- ]]; then
    n=$((10#${BASH_REMATCH[1]}))
    [[ $n -gt $MAX ]] && MAX=$n
  fi
done
printf "UC-%03d\n" $((MAX + 1))
