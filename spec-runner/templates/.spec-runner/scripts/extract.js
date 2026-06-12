#!/usr/bin/env node
'use strict';

/**
 * spec-runner extract
 *
 * 仕様書（ハイブリッド仕様YAML）から指定ブロックだけを切り出して stdout に出す。
 * LLM へ仕様を渡すときはファイル全体を読まず、必ずこのコマンドを使う。
 *
 * 使い方:
 *   node <agent-dir>/.spec-runner/scripts/extract.js <target> [--blocks 概要,定数,入出力,フロー] [--list]
 *
 *   <target> は次のいずれか:
 *     - node_id（例: 詳細.ユースケース.注文確定）
 *     - 設計書パス（docs/...）
 *     - 実装/テストパス（src/... tests/...）→ maps_to の逆引きで設計書を特定する
 *
 *   --blocks を省略すると全ブロックを出力する。--list はブロック名と行範囲のみ表示する。
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = process.cwd();
const TOOL_DIR = path.resolve(__dirname, '..');
const GRAPH_FILE = path.join(TOOL_DIR, 'scan', 'graph.json');
const SCAN_SCRIPT = path.join(__dirname, 'scan.js');

function fail(msg) {
  console.error(`extract: ${msg}`);
  process.exit(1);
}

function runScan() {
  try {
    execFileSync(process.execPath, [SCAN_SCRIPT], { stdio: ['ignore', 'ignore', 'inherit'] });
  } catch {
    // missing_maps_to で exit 1 でも graph.json 自体は生成されている
  }
}

function loadGraph() {
  if (!fs.existsSync(GRAPH_FILE)) runScan();
  if (!fs.existsSync(GRAPH_FILE)) fail(`graph.json を生成できない（${path.relative(ROOT, GRAPH_FILE)}）`);
  return JSON.parse(fs.readFileSync(GRAPH_FILE, 'utf8'));
}

function normalizeRel(p) {
  return path.relative(ROOT, path.resolve(ROOT, p));
}

/** target（node_id / docs パス / src・tests パス）からノードを特定する */
function resolveNode(graph, target) {
  if (graph.nodes[target]) return { id: target, node: graph.nodes[target] };

  const rel = normalizeRel(target);
  const byFile = Object.entries(graph.nodes).find(([, n]) => n.file === rel);
  if (byFile) return { id: byFile[0], node: byFile[1] };

  const byMaps = Object.entries(graph.nodes).filter(([, n]) => (n.maps_to || []).includes(rel));
  if (byMaps.length === 1) return { id: byMaps[0][0], node: byMaps[0][1] };
  if (byMaps.length > 1) {
    fail(`「${target}」は複数ノードに対応する。node_id で指定する:\n  ${byMaps.map(([id]) => id).join('\n  ')}`);
  }
  fail(`「${target}」に対応するノードが見つからない（node_id / docs パス / maps_to 登録済みパスで指定する）`);
}

function main() {
  const args = process.argv.slice(2);
  let target = null;
  let blockNames = null;
  let listOnly = false;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--list') { listOnly = true; continue; }
    if (a === '--blocks') { blockNames = (args[++i] || '').split(',').map(s => s.trim()).filter(Boolean); continue; }
    if (a.startsWith('--blocks=')) { blockNames = a.slice('--blocks='.length).split(',').map(s => s.trim()).filter(Boolean); continue; }
    if (!target) target = a;
  }
  if (!target) fail('対象を指定する: extract.js <node_id|パス> [--blocks 概要,フロー] [--list]');

  let graph = loadGraph();

  let { id, node } = resolveNode(graph, target);

  // 設計書が graph.json より新しければ再スキャンして読み直す
  const docPath = path.join(ROOT, node.file);
  if (fs.existsSync(docPath) && fs.statSync(docPath).mtime > new Date(graph.generated_at)) {
    runScan();
    graph = loadGraph();
    ({ id, node } = resolveNode(graph, target));
  }

  if (!node.blocks) {
    fail(`${node.file}（${id}）に仕様YAMLフェンスがない。このファイルは直接 Read する`);
  }

  if (listOnly) {
    for (const [name, range] of Object.entries(node.blocks)) {
      console.log(`${name}\t${node.file}:${range[0]}-${range[1]}`);
    }
    return;
  }

  const lines = fs.readFileSync(docPath, 'utf8').split('\n');
  const requested = blockNames || Object.keys(node.blocks);
  const out = [];
  for (const name of requested) {
    const range = node.blocks[name];
    if (!range) {
      console.error(`extract: ブロック「${name}」は ${node.file} にない（存在: ${Object.keys(node.blocks).join(', ')}）`);
      continue;
    }
    out.push(lines.slice(range[0] - 1, range[1]).join('\n'));
  }
  if (out.length === 0) fail('出力できるブロックがない');
  console.log(out.join('\n\n'));
}

main();
