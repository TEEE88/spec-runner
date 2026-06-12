#!/usr/bin/env node
'use strict';

/**
 * spec-runner impact
 *
 * 影響範囲を3段フィルタで機械的に特定し JSON で出力する。
 *   段1: graph.json の reverse_index を2階層走査（設計グラフ上の到達集合）
 *   段2: git diff との交差（実際に変更されたペアだけを乖離チェック対象に絞る）
 *   段3: 変更された関数名の抽出（LLM が読む範囲を関数単位に限定するための手がかり）
 *
 * 使い方:
 *   node <agent-dir>/.spec-runner/scripts/impact.js <target> [--diff[=<base>]]
 *
 *   <target> は node_id / 設計書パス / 実装パス（maps_to 逆引き）
 *   --diff      作業ツリーと HEAD の差分で交差を取る
 *   --diff=main 指定 ref との差分で交差を取る
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = process.cwd();
const TOOL_DIR = path.resolve(__dirname, '..');
const GRAPH_FILE = path.join(TOOL_DIR, 'scan', 'graph.json');
const SCAN_SCRIPT = path.join(__dirname, 'scan.js');

function fail(msg) {
  console.error(`impact: ${msg}`);
  process.exit(1);
}

function loadGraph() {
  if (!fs.existsSync(GRAPH_FILE)) {
    try {
      execFileSync(process.execPath, [SCAN_SCRIPT], { stdio: ['ignore', 'ignore', 'inherit'] });
    } catch { /* missing_maps_to の exit 1 でも graph.json は生成される */ }
  }
  if (!fs.existsSync(GRAPH_FILE)) fail('graph.json を生成できない');
  return JSON.parse(fs.readFileSync(GRAPH_FILE, 'utf8'));
}

function resolveNodeId(graph, target) {
  if (graph.nodes[target]) return target;
  const rel = path.relative(ROOT, path.resolve(ROOT, target));
  for (const [id, n] of Object.entries(graph.nodes)) {
    if (n.file === rel) return id;
  }
  const byMaps = Object.entries(graph.nodes).filter(([, n]) => (n.maps_to || []).includes(rel));
  if (byMaps.length === 1) return byMaps[0][0];
  if (byMaps.length > 1) {
    fail(`「${target}」は複数ノードに対応する。node_id で指定する:\n  ${byMaps.map(([id]) => id).join('\n  ')}`);
  }
  fail(`「${target}」に対応するノードが見つからない`);
}

function git(args) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8' });
}

function nodeSummary(graph, id) {
  const n = graph.nodes[id] || {};
  return { id, file: n.file || null, kind: n.kind || null, maps_to: n.maps_to || [] };
}

function main() {
  const args = process.argv.slice(2);
  let target = null;
  let diffBase = null; // null = diff なし, 'HEAD' = 作業ツリー差分
  for (const a of args) {
    if (a === '--diff') { diffBase = 'HEAD'; continue; }
    if (a.startsWith('--diff=')) { diffBase = a.slice('--diff='.length) || 'HEAD'; continue; }
    if (!target) target = a;
  }
  if (!target) fail('対象を指定する: impact.js <node_id|パス> [--diff[=<base>]]');

  const graph = loadGraph();
  const originId = resolveNodeId(graph, target);

  // 段1: グラフ到達集合（直接 = 1階層、間接 = 2階層）
  const direct = graph.reverse_index[originId] || [];
  const indirect = [...new Set(
    direct.flatMap(n => graph.reverse_index[n] || []).filter(n => !direct.includes(n) && n !== originId)
  )];
  const affectedIds = [originId, ...direct, ...indirect];
  const implFiles = [...new Set(affectedIds.flatMap(id => (graph.nodes[id] || {}).maps_to || []))];

  const result = {
    origin: nodeSummary(graph, originId),
    direct: direct.map(id => nodeSummary(graph, id)),
    indirect: indirect.map(id => nodeSummary(graph, id)),
    impl_files: implFiles,
    missing_maps_to: graph.missing_maps_to,
    lint: graph.lint || [],
    drift: graph.drift || [],
    diff: null,
  };

  // 段2・段3: git diff 交差と変更関数の抽出
  if (diffBase) {
    let changedFiles = [];
    try {
      changedFiles = git(['diff', '--name-only', diffBase]).split('\n').filter(Boolean);
    } catch (e) {
      result.diff = { base: diffBase, error: `git diff 失敗: ${String(e.message).split('\n')[0]}` };
      console.log(JSON.stringify(result, null, 2));
      return;
    }
    const changed = new Set(changedFiles);

    const pairsToCheck = [];
    const unchangedCandidates = [];
    for (const id of affectedIds) {
      const n = graph.nodes[id] || {};
      const touchedImpl = (n.maps_to || []).filter(f => changed.has(f));
      if (changed.has(n.file) || touchedImpl.length > 0) {
        pairsToCheck.push({ ...nodeSummary(graph, id), changed_impl: touchedImpl, doc_changed: changed.has(n.file) });
      } else {
        unchangedCandidates.push(id);
      }
    }

    // 段3: 変更ハンクのヘッダから関数名を抽出（@@ -l,c +l,c @@ <関数シグネチャ>）
    const changedImpl = implFiles.filter(f => changed.has(f));
    const changedFunctions = [];
    if (changedImpl.length > 0) {
      try {
        const diffText = git(['diff', '-U0', diffBase, '--', ...changedImpl]);
        let currentFile = null;
        for (const line of diffText.split('\n')) {
          const fileMatch = line.match(/^\+\+\+ b\/(.+)$/);
          if (fileMatch) { currentFile = fileMatch[1]; continue; }
          const hunkMatch = line.match(/^@@ [^@]+ @@ (.+)$/);
          if (hunkMatch && currentFile) {
            const fn = hunkMatch[1].trim();
            if (!changedFunctions.some(c => c.file === currentFile && c.context === fn)) {
              changedFunctions.push({ file: currentFile, context: fn });
            }
          }
        }
      } catch { /* 関数名抽出は補助情報。失敗しても続行 */ }
    }

    result.diff = {
      base: diffBase,
      changed_files: changedFiles,
      pairs_to_check: pairsToCheck,
      unchanged_candidates: unchangedCandidates,
      changed_functions: changedFunctions,
    };
  }

  console.log(JSON.stringify(result, null, 2));
}

main();
