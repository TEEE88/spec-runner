#!/usr/bin/env node
'use strict';

/**
 * .claude テンプレート（正本）から .github ミラーを決定論的に全生成する。
 * 手作業同期は変換漏れドリフトを繰り返したため、ミラー編集は禁止。
 * 正本を直してこれを実行 -> check-mirrors.sh で検証、が唯一の手順。
 *
 * 変換規則:
 *   rules/X.md            -> instructions/X.instructions.md（frontmatter: paths -> applyTo / description -> applyTo "**"）
 *   agents/X.md           -> agents/X.agent.md（tools 名変換・model 行削除・AskUserQuestion -> 質問）
 *   skills/X/**           -> skills/X/**（そのままコピー + パス変換）
 *   本文共通: .claude/rules/X.md -> .github/instructions/X.instructions.md、bare ルール名 -> .instructions.md、
 *             .claude/skills/ -> .github/skills/
 *   例外: agent-delegation の WebSearch 行は Copilot 非対応のため削除
 *
 * 使い方: node tools/sync-mirrors.js
 */

const fs = require('fs');
const path = require('path');

const TPL = path.resolve(__dirname, '..', 'spec-runner', 'templates');
const CLAUDE = path.join(TPL, '.claude');
const GITHUB = path.join(TPL, '.github');

const RULE_NAMES = 'code-common|code-backend|code-frontend|test-backend|test-frontend|design-docs|agent-delegation';
const TOOL_MAP = { Read: 'read', Grep: 'search', Glob: 'search', Edit: 'edit', Write: 'edit', Bash: 'execute' };

function transformBody(text) {
  return text
    .replace(new RegExp(`\\.claude/rules/(${RULE_NAMES})\\.md`, 'g'), '.github/instructions/$1.instructions.md')
    .replace(new RegExp(`\\b(${RULE_NAMES})\\.md(?!\\w)(?!\\.instructions)`, 'g'), '$1.instructions.md')
    .replace(/\.claude\/skills\//g, '.github/skills/')
    .replace(/`AskUserQuestion`/g, '質問'); // Copilot に同名ツールはない
}

function write(dest, content) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, content);
}

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

// ── rules -> instructions ───────────────────────────────────────────────────

function syncRules() {
  let n = 0;
  for (const file of walk(path.join(CLAUDE, 'rules'))) {
    if (!file.endsWith('.md')) continue;
    const base = path.basename(file, '.md');
    let text = fs.readFileSync(file, 'utf8');

    // frontmatter 変換: applyTo はそのまま / paths -> applyTo / description のみ -> applyTo "**"
    const fm = text.match(/^---\n([\s\S]*?)\n---\n/);
    if (fm) {
      const body = text.slice(fm[0].length);
      let applyTo = '**';
      const applyToMatch = fm[1].match(/applyTo:\s*"([^"]+)"/);
      const pathsMatch = fm[1].match(/paths:\s*\[([^\]]+)\]/);
      if (applyToMatch) applyTo = applyToMatch[1];
      else if (pathsMatch) applyTo = pathsMatch[1].split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).join(',');
      text = `---\napplyTo: "${applyTo}"\n---\n${body}`;
    } else {
      text = `---\napplyTo: "**"\n---\n\n${text}`;
    }

    text = transformBody(text);
    // Copilot に WebSearch はないため委任表から削除
    if (base === 'agent-delegation') {
      text = text.split('\n').filter(l => !/^\| エラー・技術調査 \|/.test(l)).join('\n');
    }

    write(path.join(GITHUB, 'instructions', `${base}.instructions.md`), text);
    n++;
  }
  return n;
}

// ── agents -> .agent.md ─────────────────────────────────────────────────────

function syncAgents() {
  let n = 0;
  for (const file of walk(path.join(CLAUDE, 'agents'))) {
    if (!file.endsWith('.md')) continue;
    const base = path.basename(file, '.md');
    let text = transformBody(fs.readFileSync(file, 'utf8'));

    // tools: Read, Grep, Bash -> tools: ["read", "search", "execute"]（model 行は削除）
    text = text.replace(/^tools:\s*(.+)$\n^model:.*$/m, (_, toolsLine) => {
      const mapped = [...new Set(toolsLine.split(',').map(t => TOOL_MAP[t.trim()]).filter(Boolean))];
      return `tools: [${mapped.map(t => `"${t}"`).join(', ')}]`;
    });

    write(path.join(GITHUB, 'agents', `${base}.agent.md`), text);
    n++;
  }
  return n;
}

// ── skills（SKILL.md・templates・references を同構造コピー） ────────────────

function syncSkills() {
  const skillsRoot = path.join(CLAUDE, 'skills');
  let n = 0;
  for (const file of walk(skillsRoot)) {
    const rel = path.relative(skillsRoot, file);
    const dest = path.join(GITHUB, 'skills', rel);
    // harness-format.md は両系運用の説明そのものなので無変換（check-mirrors も除外済み）
    if (file.endsWith('.md') && !rel.endsWith('harness-format.md')) {
      write(dest, transformBody(fs.readFileSync(file, 'utf8')));
    } else {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.copyFileSync(file, dest);
    }
    n++;
  }
  return n;
}

const counts = { rules: syncRules(), agents: syncAgents(), skillFiles: syncSkills() };
console.log(`sync-mirrors: rules ${counts.rules} / agents ${counts.agents} / skill files ${counts.skillFiles} を再生成`);
console.log('検証: bash tools/check-mirrors.sh');
