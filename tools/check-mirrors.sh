#!/bin/bash
# .claude ⇔ .github テンプレートミラーの整合チェック
# 使い方: bash tools/check-mirrors.sh（リポジトリルートで実行。問題があれば exit 1）
set -u
cd "$(dirname "$0")/../spec-runner/templates" || exit 1
NG=0

# 1. ペア存在チェック
for r in .claude/rules/*.md; do
  b=$(basename "$r" .md)
  [ -f ".github/instructions/$b.instructions.md" ] || { echo "MISSING: .github/instructions/$b.instructions.md"; NG=1; }
done
for a in .claude/agents/*.md; do
  b=$(basename "$a" .md)
  [ -f ".github/agents/$b.agent.md" ] || { echo "MISSING: .github/agents/$b.agent.md"; NG=1; }
done
for s in .claude/skills/*/; do
  n=$(basename "$s")
  [ -f ".github/skills/$n/SKILL.md" ] || { echo "MISSING: .github/skills/$n/SKILL.md"; NG=1; }
done

# 2. .github 側に bare ルール名（X.md のまま）が残っていないか
LEFT=$(grep -rno -E "\b(code-common|code-backend|code-frontend|test-backend|test-frontend|design-docs|agent-delegation)\.md\b" .github/ | grep -v "\.instructions\.md")
[ -n "$LEFT" ] && { echo "未変換の bare ルール名:"; echo "$LEFT"; NG=1; }

# 3. .github 側に .claude/rules/ ・.claude/agents/ 参照が残っていないか
#    （harness-format.md は両系運用の説明として .claude 言及が正当なので除外）
LEFT=$(grep -rn "\.claude/rules/\|\.claude/agents/" .github/ --exclude=harness-format.md || true)
[ -n "$LEFT" ] && { echo ".claude パス参照の残存:"; echo "$LEFT"; NG=1; }

[ $NG -eq 0 ] && echo "check-mirrors: OK（rules $(ls .claude/rules/*.md | wc -l | tr -d ' ') / agents $(ls .claude/agents/*.md | wc -l | tr -d ' ') / skills $(ls -d .claude/skills/*/ | wc -l | tr -d ' ')）"
exit $NG
