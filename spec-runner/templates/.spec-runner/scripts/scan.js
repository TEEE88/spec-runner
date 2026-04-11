#!/usr/bin/env node
'use strict';

/**
 * spec-runner scan
 *
 * docs/**\/*.md の frontmatter（spec_runner: セクション）を静的解析し、
 * 依存グラフを .spec-runner/scan/graph.json にキャッシュする。
 *
 * 出力:
 *   .spec-runner/scan/graph.json
 *
 * 使い方:
 *   node .spec-runner/scripts/scan.js
 */

const fs = require('fs');
const path = require('path');

const ROOT = process.cwd();
const DOCS_DIR = path.join(ROOT, 'docs');
const OUTPUT_DIR = path.join(ROOT, '.spec-runner', 'scan');
const OUTPUT_FILE = path.join(OUTPUT_DIR, 'graph.json');

// ── ファイル収集 ────────────────────────────────────────────────────────────

function findMdFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) results.push(...findMdFiles(full));
    else if (entry.name.endsWith('.md')) results.push(full);
  }
  return results;
}

// ── frontmatter パーサー ────────────────────────────────────────────────────

function parseSpecRunnerFrontmatter(content) {
  const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) return null;

  const fm = fmMatch[1];
  if (!fm.includes('spec_runner:')) return null;

  // spec_runner: セクションを抽出（次のトップレベルキーまで）
  const srMatch = fm.match(/spec_runner:\n([\s\S]*?)(?=\n\S|$)/);
  if (!srMatch) return null;
  const srBlock = srMatch[1];

  const nodeIdMatch = srBlock.match(/^\s+node_id:\s*(.+)$/m);
  if (!nodeIdMatch) return null;

  const kindMatch = srBlock.match(/^\s+kind:\s*(.+)$/m);

  return {
    node_id: nodeIdMatch[1].trim(),
    kind: kindMatch ? kindMatch[1].trim() : null,
    depends_on: parseYamlList(srBlock, 'depends_on'),
    maps_to: parseYamlList(srBlock, 'maps_to'),
  };
}

function parseYamlList(block, key) {
  const re = new RegExp(`^([ \\t]+)${key}:\\s*(.*)$`, 'm');
  const keyMatch = block.match(re);
  if (!keyMatch) return [];

  const inlineVal = keyMatch[2].trim();

  // インライン配列: [a, b, c]
  if (inlineVal.startsWith('[')) {
    return inlineVal.replace(/[\[\]]/g, '').split(',').map(s => s.trim()).filter(Boolean);
  }

  // マルチライン配列: - item
  const keyIndex = block.indexOf(keyMatch[0]);
  const afterKey = block.slice(keyIndex + keyMatch[0].length);
  const items = [];
  for (const line of afterKey.split('\n')) {
    const itemMatch = line.match(/^\s+-\s+(.+)$/);
    if (itemMatch) {
      items.push(itemMatch[1].trim());
    } else if (line.trim() !== '') {
      break; // 別のキーが始まったら終了
    }
  }
  return items;
}

// ── メイン ──────────────────────────────────────────────────────────────────

function main() {
  const files = findMdFiles(DOCS_DIR);

  const graph = {
    generated_at: new Date().toISOString(),
    nodes: {},         // node_id → { file, kind, depends_on, maps_to }
    reverse_index: {}, // node_id → [依存元 node_id のリスト]（影響範囲検索用）
    missing_maps_to: [], // { source, node_id, missing } 存在しないファイル参照
  };

  for (const file of files) {
    let content;
    try {
      content = fs.readFileSync(file, 'utf8');
    } catch {
      continue;
    }

    const fm = parseSpecRunnerFrontmatter(content);
    if (!fm) continue;

    const relPath = path.relative(ROOT, file);
    const { node_id, kind, depends_on, maps_to } = fm;

    graph.nodes[node_id] = { file: relPath, kind, depends_on, maps_to };

    // リバースインデックスを構築（A が B に depends_on → reverse_index[B].push(A)）
    for (const dep of depends_on) {
      if (!graph.reverse_index[dep]) graph.reverse_index[dep] = [];
      graph.reverse_index[dep].push(node_id);
    }

    // maps_to の実在チェック
    for (const mapped of maps_to) {
      const mappedPath = path.join(ROOT, mapped);
      // 末尾スラッシュ付きはディレクトリ
      const exists = mapped.endsWith('/')
        ? fs.existsSync(mappedPath)
        : fs.existsSync(mappedPath);
      if (!exists) {
        graph.missing_maps_to.push({ source: relPath, node_id, missing: mapped });
      }
    }
  }

  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(graph, null, 2));

  const nodeCount = Object.keys(graph.nodes).length;
  const rel = path.relative(ROOT, OUTPUT_FILE);
  console.log(`spec-runner scan: ${nodeCount} nodes indexed → ${rel}`);

  if (graph.missing_maps_to.length > 0) {
    console.warn(`\nmaps_to integrity: ${graph.missing_maps_to.length} missing reference(s)`);
    for (const m of graph.missing_maps_to) {
      console.warn(`  MISSING  ${m.missing}`);
      console.warn(`           in ${m.source} (${m.node_id})`);
    }
    process.exit(1);
  }
}

main();
