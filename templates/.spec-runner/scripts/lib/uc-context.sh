#!/usr/bin/env bash
# UC コンテキスト: 現在ブランチ（feature/UC-NNN-xxx）に対応する「関連ファイルのパス」を返す。
# ステップ（分析・仕様策定・実装 等）で AI が「どのファイルを読むか」を 1 回の実行で取得するために使う。
# 構成: docs/02_ユースケース仕様/<カテゴリ>/UC-NNN-xxx.md（1 UC = 1 ファイル。実装方針・タスクはこの .md の一番下に記載）
# 出力: FEATURE_SPEC, FEATURE_DIR を JSON またはテキスト
# 使用: uc-context.sh [--json] [--paths-only]

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"

PATHS_ONLY=false
JSON_MODE=false
for a in "$@"; do
  case "$a" in
    --paths-only) PATHS_ONLY=true ;;
    --json)       JSON_MODE=true ;;
  esac
done

BRANCH=$(git branch --show-current 2>/dev/null || echo "")
# ブランチ接頭辞は project.json の naming.branch_prefix。無ければ feature
BRANCH_PREFIX="feature"
if [[ -f ".spec-runner/project.json" ]] && command -v jq >/dev/null 2>&1; then
  p=$(jq -r '.naming.branch_prefix // empty' .spec-runner/project.json 2>/dev/null)
  [[ -n "$p" ]] && BRANCH_PREFIX="$p"
fi
# 正規表現は接頭辞/UC-NNN-xxx 形式（接頭辞は英数字とハイフンのみ想定）
if [[ ! "$BRANCH" =~ ^${BRANCH_PREFIX}/(UC-[0-9]{3}-[a-z0-9-]+)$ ]]; then
  echo "ERROR: UC 用ブランチではありません。${BRANCH_PREFIX}/UC-NNN-xxx 形式で作成してください（例: ブランチ作成 UC-001 order-placement）。接頭辞は project.json の naming.branch_prefix で変更可。" >&2
  exit 1
fi

# feature/UC-001-order-placement → UC-001-order-placement
UC_BASE="${BASH_REMATCH[1]}"
UC_DIR="$REPO_ROOT/docs/02_ユースケース仕様"
# カテゴリフォルダ内の UC-NNN-xxx.md を探す（docs/02_ユースケース仕様/<カテゴリ>/UC-NNN-xxx.md）
FEATURE_SPEC=""
for f in "$UC_DIR"/*/"${UC_BASE}.md"; do
  [[ -f "$f" ]] && FEATURE_SPEC="$f" && break
done
if [[ -n "$FEATURE_SPEC" ]]; then
  FEATURE_DIR=$(dirname "$FEATURE_SPEC")
else
  FEATURE_DIR="$UC_DIR"
fi

if [[ "$PATHS_ONLY" != true ]]; then
  if [[ -z "$FEATURE_SPEC" || ! -f "$FEATURE_SPEC" ]]; then
    echo "ERROR: UC 仕様書がありません。docs/02_ユースケース仕様/<カテゴリ>/${UC_BASE}.md のいずれかに配置してください。" >&2
    exit 1
  fi
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g'
}
if [[ "$JSON_MODE" == true ]]; then
  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg repo_root "$REPO_ROOT" \
      --arg branch "$BRANCH" \
      --arg feature_spec "$FEATURE_SPEC" \
      --arg feature_dir "$FEATURE_DIR" \
      '{REPO_ROOT:$repo_root,BRANCH:$branch,FEATURE_SPEC:$feature_spec,FEATURE_DIR:$feature_dir}'
  else
    printf '{"REPO_ROOT":"%s","BRANCH":"%s","FEATURE_SPEC":"%s","FEATURE_DIR":"%s"}\n' \
      "$(json_escape "$REPO_ROOT")" "$(json_escape "$BRANCH")" "$(json_escape "$FEATURE_SPEC")" "$(json_escape "$FEATURE_DIR")"
  fi
else
  echo "REPO_ROOT: $REPO_ROOT"
  echo "BRANCH: $BRANCH"
  echo "FEATURE_SPEC: $FEATURE_SPEC"
  echo "FEATURE_DIR: $FEATURE_DIR"
fi
