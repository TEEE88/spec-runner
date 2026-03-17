#!/usr/bin/env bash
# OpenAPI から型・クライアントを生成する。
# ターゲットは「今のドキュメント」(.spec-runner/openapi-generator-targets.json) にだけ載せる。
# 対話で generator と output を聞き、生成後に「名前を付けて保存」するとドキュメントに追記され、次から名前で呼べる。
# 使用例:
#   ./openapi-generate.sh              # 対話: 既存から選択 or 新規（generator/output を聞いて保存）
#   ./openapi-generate.sh typescript   # ドキュメントに登録した名前で生成
#   ./openapi-generate.sh --generator python --output src/api_python  # 直接指定（終了時に「保存する？」と聞く）
#   ./openapi-generate.sh --list

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)}"
[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

INPUT_SPEC="${REPO_ROOT}/docs/06_API仕様/openapi.yaml"
CONFIG="${REPO_ROOT}/.spec-runner/openapi-generator-targets.json"

if [[ ! -f "$INPUT_SPEC" ]]; then
  echo "openapi-generate: openapi.yaml がありません（docs/06_API仕様/openapi.yaml）。" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "openapi-generate: 対話でドキュメントを更新するために jq が必要です（brew install jq）。" >&2
  exit 1
fi

# 設定ファイルを用意（無ければ空の targets）
ensure_config() {
  if [[ ! -f "$CONFIG" ]]; then
    mkdir -p "$(dirname "$CONFIG")"
    echo '{"targets":{},"inputSpec":"docs/06_API仕様/openapi.yaml"}' > "$CONFIG"
  fi
}

# JSON から generator と output を取得
get_from_config() {
  local target="$1"
  if [[ -f "$CONFIG" ]]; then
    local g o
    g=$(jq -r --arg t "$target" '.targets[$t].generator // empty' "$CONFIG" 2>/dev/null)
    o=$(jq -r --arg t "$target" '.targets[$t].output // empty' "$CONFIG" 2>/dev/null)
    if [[ -n "$g" ]] && [[ -n "$o" ]]; then
      echo "${g}|${o}"
    fi
  fi
}

# ドキュメントにターゲットを 1 件追加
save_target() {
  local name="$1"
  local generator="$2"
  local output="$3"
  local desc="${4:-}"
  ensure_config
  if [[ -z "$name" ]]; then return; fi
  # 既存 targets にマージ。description は任意。
  jq --arg n "$name" --arg g "$generator" --arg o "$output" --arg d "$desc" \
    '.targets[$n] = (if $d != "" then {"generator":$g,"output":$o,"description":$d} else {"generator":$g,"output":$o} end)' \
    "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
  echo "  → .spec-runner/openapi-generator-targets.json に「$name」を追加しました。"
}

# 生成実行（共通）
run_generate() {
  local generator="$1"
  local output="$2"
  echo "OpenAPI から生成: generator=$generator, output=$output"
  npx --yes @openapitools/openapi-generator-cli@latest generate \
    -i "$INPUT_SPEC" \
    -g "$generator" \
    -o "$REPO_ROOT/$output" \
    --additional-properties=supportsES6=true
  echo "生成完了: $output"
}

list_targets() {
  ensure_config
  echo "登録済みターゲット（.spec-runner/openapi-generator-targets.json）:"
  if ! jq -e '.targets | length > 0' "$CONFIG" >/dev/null 2>&1; then
    echo "  （なし）対話で追加してください: ./openapi-generate.sh"
  else
    jq -r '.targets | to_entries[] | "  \(.key): generator=\(.value.generator), output=\(.value.output)"' "$CONFIG" 2>/dev/null || true
  fi
  echo ""
  echo "直接指定: --generator <name> --output <dir>  例: --generator ruby --output lib/api_ruby"
  echo "一覧: https://openapi-generator.tech/docs/generators/"
  exit 0
}

# 対話: 新規ターゲット（generator / output を聞き、生成してから名前を付けて保存）
interactive_new() {
  local g o name desc
  echo "新規ターゲットを追加します。"
  read -r -p "Generator 名 (例: typescript-fetch, python, go): " g
  g=$(echo "$g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -z "$g" ]]; then
    echo "Generator 名が空のため中止しました。" >&2
    exit 1
  fi
  read -r -p "出力ディレクトリ (例: src/api-client-ts): " o
  o=$(echo "$o" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -z "$o" ]]; then
    echo "出力ディレクトリが空のため中止しました。" >&2
    exit 1
  fi
  run_generate "$g" "$o"
  echo ""
  read -r -p "この組み合わせをドキュメントに保存しますか？名前 (空白でスキップ): " name
  name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -n "$name" ]]; then
    read -r -p "説明 (任意): " desc
    save_target "$name" "$g" "$o" "$desc"
  fi
}

# 引数解析
GENERATOR=""
OUTPUT=""
TARGET="${OPENAPI_TARGET:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list|-l) list_targets ;;
    -h|--help)
      echo "使用法: openapi-generate.sh [ターゲット名] | [--generator <name> --output <dir>]"
      echo "  引数なし     → 対話: 登録済みから選択 or 新規追加（generator/output を聞いてドキュメントに保存）"
      echo "  ターゲット名 → ドキュメントに登録した名前で生成"
      echo "  --generator X --output Y → 直接生成。終了時に「ドキュメントに保存する？」と聞く"
      echo ""
      list_targets
      ;;
    --generator) GENERATOR="$2"; shift 2 ;;
    --output)    OUTPUT="$2";   shift 2 ;;
    --*)
      echo "openapi-generate: 不明なオプション $1" >&2
      exit 1
      ;;
    *) TARGET="$1"; shift ;;
  esac
done

# 直接指定で生成 → 終了時に「保存する？」と聞く
if [[ -n "$GENERATOR" ]] && [[ -n "$OUTPUT" ]]; then
  run_generate "$GENERATOR" "$OUTPUT"
  if [[ -t 0 ]]; then
    echo ""
    read -r -p "この組み合わせをドキュメントに保存しますか？名前 (空白でスキップ): " name
    name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -n "$name" ]]; then
      read -r -p "説明 (任意): " desc
      save_target "$name" "$GENERATOR" "$OUTPUT" "$desc"
    fi
  fi
  exit 0
fi

# ターゲット名指定 → ドキュメントから取得して生成
if [[ -n "$TARGET" ]]; then
  pair=$(get_from_config "$TARGET")
  if [[ -z "$pair" ]]; then
    echo "openapi-generate: 登録されていないターゲット「$TARGET」" >&2
    echo "  --list で一覧。または引数なしで対話し、この名前で保存してください。" >&2
    exit 1
  fi
  IFS='|' read -r GENERATOR OUTPUT <<< "$pair"
  run_generate "$GENERATOR" "$OUTPUT"
  exit 0
fi

# 引数なし → 対話
ensure_config
keys=($(jq -r '.targets | keys[]' "$CONFIG" 2>/dev/null || true))

if [[ ${#keys[@]} -eq 0 ]]; then
  # まだ 1 件もない → 新規追加フローへ
  interactive_new
  exit 0
fi

echo "ターゲットを選ぶか、新規追加します:"
for i in "${!keys[@]}"; do
  echo "  $((i+1))) ${keys[$i]}"
done
echo "  n) 新規追加（generator / output を入力してドキュメントに保存）"
read -r -p "番号または名前 [1]: " ans
ans="${ans:-1}"

if [[ "$ans" == "n" ]] || [[ "$ans" == "N" ]] || [[ "$ans" == "新規" ]]; then
  interactive_new
  exit 0
fi

if [[ "$ans" =~ ^[0-9]+$ ]] && [[ "$ans" -ge 1 ]] && [[ "$ans" -le ${#keys[@]} ]]; then
  TARGET="${keys[$((ans-1))]}"
else
  TARGET="$ans"
fi

pair=$(get_from_config "$TARGET")
if [[ -z "$pair" ]]; then
  echo "openapi-generate: 登録されていないターゲット「$TARGET」" >&2
  exit 1
fi
IFS='|' read -r GENERATOR OUTPUT <<< "$pair"
run_generate "$GENERATOR" "$OUTPUT"
