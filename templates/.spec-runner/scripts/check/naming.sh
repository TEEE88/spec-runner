#!/usr/bin/env bash
# 命名規則チェック（Section 8-3 簡易版）
# ブランチ名・フォルダ名・禁止パターンを検証する。

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
errors=0

# ① ブランチ名チェック
check_branch_name() {
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "nobranch")
  local bp="feature"
  local other_work="work/.+|infra/.+|cicd/.+"
  if [[ -f "$REPO_ROOT/.spec-runner/project.json" ]] && command -v jq >/dev/null 2>&1; then
    p=$(jq -r '.naming.branch_prefix // empty' "$REPO_ROOT/.spec-runner/project.json" 2>/dev/null); [[ -n "$p" ]] && bp="$p"
    ow=$(jq -r '.naming.other_work_prefixes[]? | . + "/.+"' "$REPO_ROOT/.spec-runner/project.json" 2>/dev/null | tr '\n' '|' | sed 's/|$//'); [[ -n "$ow" ]] && other_work="$ow"
  fi
  local valid="^(main|develop|${bp}/(UC-[0-9]{3}-.+|${other_work})|fix/UC-[0-9]{3}-.+|release/[0-9]+\.[0-9]+\.[0-9]+.*|hotfix/[0-9]+\.[0-9]+\.[0-9]+-.+)$"
  if [[ "$branch" != "nobranch" ]] && ! echo "$branch" | grep -qE "$valid"; then
    echo "NAMING: ブランチ名「$branch」が規則違反" >&2
    return 1
  fi
  return 0
}

# ② フォルダ名チェック（src が存在する場合のみ・kebab-case）
check_folder_names() {
  local n=0
  [[ -d "src" ]] || return 0
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    base=$(basename "$dir")
    if ! echo "$base" | grep -qE '^[a-z][a-z0-9-]*$'; then
      echo "NAMING: フォルダ名「$dir」はkebab-caseで命名してください" >&2
      n=$((n+1))
    fi
  done < <(find src/ -type d 2>/dev/null || true)
  return $n
}

check_branch_name || errors=$((errors+1))
check_folder_names || errors=$((errors+1))

if [[ $errors -eq 0 ]]; then
  echo "✅ 命名規則チェック: 問題なし"
  exit 0
else
  exit 1
fi
