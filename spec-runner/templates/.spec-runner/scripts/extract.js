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
 *   <target>: node_id / 設計書パス（docs/...）/ 実装・テストパス（maps_to 逆引き）
 *   --blocks 省略時は全ブロック。--list はブロック名と行範囲のみ表示。
 */

const fs = require('fs');
const path = require('path');
const lib = require('./lib.js');

const TOOL = 'extract';

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
  if (!target) lib.fail(TOOL, '対象を指定する: extract.js <node_id|パス> [--blocks 概要,フロー] [--list]');

  let graph = lib.loadGraph(TOOL);
  let { id, node } = lib.resolveNode(TOOL, graph, target);

  // 設計書が graph.json より新しければ再スキャンして読み直す
  const docPath = path.join(lib.ROOT, node.file);
  if (fs.existsSync(docPath) && fs.statSync(docPath).mtime > new Date(graph.generated_at)) {
    lib.runScan();
    graph = lib.loadGraph(TOOL);
    ({ id, node } = lib.resolveNode(TOOL, graph, target));
  }

  if (!node.blocks) {
    lib.fail(TOOL, `${node.file}（${id}）に仕様YAMLフェンスがない。このファイルは直接 Read する`);
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
  if (out.length === 0) lib.fail(TOOL, '出力できるブロックがない');
  console.log(out.join('\n\n'));
}

main();
