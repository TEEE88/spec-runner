#!/usr/bin/env node
'use strict';

/**
 * spec-runner render
 *
 * 仕様YAMLから図を生成する。図は手で書かない・生成する。
 *
 * 生成先:
 *   各詳細設計の末尾 — フロー / 状態.遷移 の Mermaid 図をマーカー区間に埋め込み
 *                      （<!-- spec-runner:figure:start/end --> をツールが管理。手で編集しない）
 *   docs/_generated/dashboard.md    — 全ノードの健康表・要件カバレッジ・警告一覧
 *   docs/_generated/dependencies.md — depends_on の依存グラフ
 *
 * 使い方: node render.js [-q]（-q は要約1行のみ出力）
 */

const fs = require('fs');
const path = require('path');
const lib = require('./lib.js');
const { parseListOfMaps, ROOT } = lib;

const OUT_DIR = path.join(ROOT, 'docs', '_generated');
const MARK_START = '<!-- spec-runner:figure:start -->';
const MARK_END = '<!-- spec-runner:figure:end -->';

function esc(s) {
  return String(s).replace(/"/g, "'").replace(/[\[\]]/g, '').slice(0, 50);
}

function readBlock(lines, node, name) {
  if (!node.blocks || !node.blocks[name]) return '';
  const [s, e] = node.blocks[name];
  return lines.slice(s - 1, e).join('\n');
}

// ── flowchart 生成（フロー → Mermaid） ─────────────────────────────────────

function flowToMermaid(flowText) {
  const items = parseListOfMaps(flowText);
  if (items.length === 0) return null;

  // ノード宣言の直後にそのノードからの辺を出力する（レイアウトエンジンが隣接関係を把握できる）
  const lines = ['flowchart TD', '  S(["開始"])'];
  let n = 0;
  let prev = 'S';
  let beforeLoop = null;
  let loopId = null;
  let pendingExit = null;
  let endedWithNext = false;

  const closeLoop = () => {
    if (!loopId) return;
    lines.push('  end');
    if (beforeLoop) lines.push(`  ${beforeLoop} --> ${loopId}`);
    if (pendingExit) {
      const xid = `x${n++}`;
      lines.push(`  ${xid}(["${esc(pendingExit)}"])`);
      lines.push(`  ${loopId} -->|${esc(pendingExit)}| ${xid}`);
      prev = xid;
    } else {
      prev = loopId;
    }
    loopId = null;
    pendingExit = null;
  };

  for (const item of items) {
    if (item.loop !== undefined || item.tx !== undefined) {
      closeLoop();
      const id = `g${n++}`;
      const label = item.loop !== undefined ? `loop: ${esc(item.loop)}` : `tx: ${esc(item.tx)}`;
      lines.push(`  subgraph ${id}["${label}"]`);
      lines.push('  direction TB');
      beforeLoop = prev;
      prev = null;
      loopId = id;
      pendingExit = item.exit || null;
      continue;
    }
    if (loopId && item.step !== undefined) closeLoop();

    const id = `s${n++}`;
    lines.push(`  ${id}["${esc(item.do || item.case || '')}"]`);
    if (prev) {
      lines.push(item.on ? `  ${prev} -->|${esc(item.on)}| ${id}` : `  ${prev} --> ${id}`);
    }
    if (item.error) {
      const eid = `e${n++}`;
      const [cond, type] = String(item.error).split('->').map(s => s.trim());
      lines.push(`  ${eid}{{"${esc(type || item.error)}"}}:::err`);
      lines.push(`  ${id} -. ${esc(cond)} .-> ${eid}`);
    }
    endedWithNext = false;
    if (item.next && item.next !== 'なし') {
      const nid = `t${n++}`;
      lines.push(`  ${nid}[/"${esc(item.next)}"/]:::nav`);
      lines.push(`  ${id} --> ${nid}`);
      endedWithNext = true;
    }
    prev = id;
  }
  closeLoop();
  if (!endedWithNext && prev) {
    lines.push('  E(["終了"])');
    lines.push(`  ${prev} --> E`);
  }

  lines.push('  classDef err fill:#ffe6e6,stroke:#cc3333,color:#990000;');
  lines.push('  classDef nav fill:#e6f0ff,stroke:#3366cc,color:#003399;');
  return '---\ntitle: フロー\n---\n' + lines.join('\n');
}

// ── stateDiagram 生成（状態.遷移 → Mermaid） ───────────────────────────────

function stateToMermaid(stateText) {
  const transitions = [...stateText.matchAll(/\{\s*from:\s*([^,}]+),\s*to:\s*([^,}]+),\s*when:\s*([^}]+)\}/g)];
  if (transitions.length === 0) return null;
  const out = ['---', 'title: 状態遷移', '---', 'stateDiagram-v2'];
  out.push(`  [*] --> ${esc(transitions[0][1].trim())}`);
  for (const [, from, to, when] of transitions) {
    out.push(`  ${esc(from.trim())} --> ${esc(to.trim())}: ${esc(when.trim())}`);
  }
  return out.join('\n');
}

// ── 設計書末尾への埋め込み ──────────────────────────────────────────────────

/** マーカー区間を差し替える。図がなければ区間を除去する。変更があったときだけ書く */
function embedFigure(docPath, diagrams) {
  let text = fs.readFileSync(docPath, 'utf8');
  const startIdx = text.indexOf(MARK_START);
  const endIdx = text.indexOf(MARK_END);

  let section = '';
  if (diagrams.length > 0) {
    section = [
      MARK_START,
      '',
      '## 図（自動生成・編集禁止）',
      '',
      ...diagrams.flatMap((d, i) => [
        ...(i > 0 ? ['---', ''] : []),
        '```mermaid', d, '```', '',
      ]),
      MARK_END,
    ].join('\n');
  }

  let next;
  if (startIdx !== -1 && endIdx !== -1) {
    const before = text.slice(0, startIdx).replace(/\n+$/, '\n\n');
    const after = text.slice(endIdx + MARK_END.length).replace(/^\n+/, '\n');
    next = section ? before + section + after : before.replace(/\n+$/, '\n') + after.replace(/^\n+/, '');
  } else if (section) {
    next = text.replace(/\n*$/, '\n\n') + section + '\n';
  } else {
    return false;
  }

  if (next !== text) {
    fs.writeFileSync(docPath, next);
    return true;
  }
  return false;
}

// ── メイン ──────────────────────────────────────────────────────────────────

function main() {
  const quiet = process.argv.includes('-q') || process.argv.includes('--quiet');
  const g = lib.loadGraph('render');
  fs.mkdirSync(OUT_DIR, { recursive: true });

  // 1. 各詳細設計へ図を埋め込み
  let embedded = 0;
  for (const node of Object.values(g.nodes)) {
    if (!node.blocks) continue;
    const docPath = path.join(ROOT, node.file);
    if (!fs.existsSync(docPath)) continue;
    const lines = fs.readFileSync(docPath, 'utf8').split('\n');
    const diagrams = [
      flowToMermaid(readBlock(lines, node, 'フロー')),
      stateToMermaid(readBlock(lines, node, '状態')),
    ].filter(Boolean);
    if (embedFigure(docPath, diagrams)) embedded++;
  }

  // 2. dashboard.md
  const warnByFile = {};
  for (const w of [...g.lint, ...g.drift]) {
    warnByFile[w.file] = warnByFile[w.file] || { lint: 0, drift: 0 };
  }
  for (const w of g.lint) warnByFile[w.file].lint++;
  for (const w of g.drift) warnByFile[w.file].drift++;

  const dash = [];
  dash.push('# spec-runner ダッシュボード');
  dash.push('');
  dash.push(`自動生成（${g.generated_at}）。手で編集しない。再生成: \`node .spec-runner/scripts/render.js\``);
  dash.push('');
  dash.push('## ノード健康表');
  dash.push('');
  dash.push('| node_id | kind | テスト数 | lint | drift | satisfies |');
  dash.push('|---|---|---|---|---|---|');
  for (const [id, node] of Object.entries(g.nodes)) {
    const w = warnByFile[node.file] || { lint: 0, drift: 0 };
    let testCount = '-';
    if (node.blocks) {
      const docPath = path.join(ROOT, node.file);
      const lines = fs.existsSync(docPath) ? fs.readFileSync(docPath, 'utf8').split('\n') : [];
      testCount = String((readBlock(lines, node, 'テスト仕様').match(/-\s+id:\s*T-/g) || []).length);
    }
    const mark = (c) => (c === 0 ? 'OK' : `${c} 件`);
    dash.push(`| ${id} | ${node.kind || '-'} | ${testCount} | ${mark(w.lint)} | ${mark(w.drift)} | ${(node.satisfies || []).join(', ') || '-'} |`);
  }
  dash.push('');
  dash.push('## 要件カバレッジ');
  dash.push('');
  const reqs = Object.entries(g.requirements || {});
  if (reqs.length === 0) {
    dash.push('要件定義に REQ-XX が定義されていない。');
  } else {
    dash.push('| REQ | 内容 | 実装する設計書 |');
    dash.push('|---|---|---|');
    for (const [req, info] of reqs) {
      dash.push(`| ${req} | ${info.text} | ${info.satisfied_by.join(', ') || '**未実装**'} |`);
    }
  }
  dash.push('');
  dash.push('## 警告');
  dash.push('');
  const sections = [
    ['missing_maps_to', g.missing_maps_to.map(m => `${m.missing}（${m.node_id}）`)],
    ['unmapped（仕様なきコード）', g.unmapped || []],
    ['lint', g.lint.map(w => `[${w.rule}] ${w.file}: ${w.message}`)],
    ['drift', g.drift.map(w => `[${w.rule}] ${w.file}: ${w.message}`)],
  ];
  let anyWarn = false;
  for (const [name, list] of sections) {
    if (list.length === 0) continue;
    anyWarn = true;
    dash.push(`### ${name}（${list.length}）`);
    dash.push('');
    for (const item of list.slice(0, 30)) dash.push(`- ${item}`);
    if (list.length > 30) dash.push(`- ... 他 ${list.length - 30} 件`);
    dash.push('');
  }
  if (!anyWarn) dash.push('警告なし。');
  fs.writeFileSync(path.join(OUT_DIR, 'dashboard.md'), dash.join('\n') + '\n');

  // 3. dependencies.md
  const dep = [];
  dep.push('# 依存グラフ（自動生成）');
  dep.push('');
  dep.push('```mermaid');
  dep.push('graph TD');
  const ids = Object.keys(g.nodes);
  const alias = new Map(ids.map((id, i) => [id, `n${i}`]));
  for (const id of ids) {
    dep.push(`  ${alias.get(id)}["${esc(id)}"]`);
  }
  for (const [id, node] of Object.entries(g.nodes)) {
    for (const d of node.depends_on || []) {
      if (alias.has(d)) dep.push(`  ${alias.get(id)} --> ${alias.get(d)}`);
    }
  }
  dep.push('```');
  fs.writeFileSync(path.join(OUT_DIR, 'dependencies.md'), dep.join('\n') + '\n');

  console.log(quiet
    ? `spec-runner render: ${ids.length} nodes rendered`
    : `spec-runner render: 図を ${embedded} 設計書へ埋め込み / docs/_generated/（dashboard / dependencies）更新`);
}

main();
