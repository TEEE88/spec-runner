'use strict';

/**
 * spec-runner 共有ライブラリ
 * scan.js / extract.js / impact.js / render.js が使うパーサとグラフ I/O。
 * 単体では実行しない。
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = process.cwd();
const DOCS_DIR = path.join(ROOT, 'docs');
const TOOL_DIR = path.resolve(__dirname, '..');
const GRAPH_FILE = path.join(TOOL_DIR, 'scan', 'graph.json');
const SCAN_SCRIPT = path.join(__dirname, 'scan.js');

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

/** ファイルまたはディレクトリ配下の全ファイルパスを返す */
function collectFiles(p) {
  if (!fs.existsSync(p)) return [];
  if (fs.statSync(p).isFile()) return [p];
  const results = [];
  for (const entry of fs.readdirSync(p, { withFileTypes: true })) {
    const full = path.join(p, entry.name);
    if (entry.isDirectory()) results.push(...collectFiles(full));
    else if (entry.isFile()) results.push(full);
  }
  return results;
}

// ── frontmatter パーサー ────────────────────────────────────────────────────

function parseSpecRunnerFrontmatter(content) {
  const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) return null;

  const fm = fmMatch[1];
  if (!fm.includes('spec_runner:')) return null;

  const srMatch = fm.match(/spec_runner:\n([\s\S]*?)(?=\n\S|$)/);
  if (!srMatch) return null;
  const srBlock = srMatch[1];

  const nodeIdMatch = srBlock.match(/^\s+node_id:\s*(.+)$/m);
  if (!nodeIdMatch) return null;

  return {
    node_id: nodeIdMatch[1].trim(),
    depends_on: parseYamlList(srBlock, 'depends_on'),
    maps_to: parseYamlList(srBlock, 'maps_to'),
  };
}

function parseYamlList(block, key) {
  // 注意: \s は改行を跨ぐため使わない（マルチライン配列の1件目が値側に食われる）
  const re = new RegExp(`^[ \\t]+${key}:[ \\t]*(.*)$`, 'm');
  const keyMatch = block.match(re);
  if (!keyMatch) return [];

  const inlineVal = keyMatch[1].trim();
  if (inlineVal.startsWith('[')) {
    return inlineVal.replace(/[\[\]]/g, '').split(',').map(s => s.trim()).filter(Boolean);
  }

  const afterKey = block.slice(keyMatch.index + keyMatch[0].length);
  const items = [];
  for (const line of afterKey.split('\n')) {
    const itemMatch = line.match(/^\s+-\s+(.+)$/);
    if (itemMatch) {
      items.push(itemMatch[1].trim());
    } else if (line.trim() !== '') {
      break;
    }
  }
  return items;
}

// ── 仕様YAMLブロック解析 ────────────────────────────────────────────────────

/** frontmatter 直後の最初の ```yaml フェンスのブロック行範囲（1始まり・両端含む）を返す */
function parseSpecBlocks(lines) {
  let fmEnd = 0;
  if (lines[0] === '---') {
    for (let i = 1; i < lines.length; i++) {
      if (/^---\s*$/.test(lines[i])) { fmEnd = i; break; }
    }
  }

  let fenceStart = -1;
  let fenceEnd = -1;
  for (let i = fmEnd + 1; i < lines.length; i++) {
    if (fenceStart === -1) {
      if (/^```ya?ml\s*$/.test(lines[i])) fenceStart = i;
    } else if (/^```\s*$/.test(lines[i])) {
      fenceEnd = i;
      break;
    }
  }
  if (fenceStart === -1 || fenceEnd === -1) return null;

  const lastNonEmpty = (idx) => {
    while (idx > fenceStart && lines[idx].trim() === '') idx -= 1;
    return idx;
  };

  const blocks = {};
  const order = [];
  let current = null;
  let currentStart = -1;
  for (let i = fenceStart + 1; i < fenceEnd; i++) {
    const m = lines[i].match(/^([^\s#-][^:]*):/);
    if (!m) continue;
    if (current) blocks[current] = [currentStart + 1, lastNonEmpty(i - 1) + 1];
    current = m[1].trim();
    currentStart = i;
    order.push(current);
  }
  if (current) blocks[current] = [currentStart + 1, lastNonEmpty(fenceEnd - 1) + 1];

  return { blocks, order };
}

/** frontmatter 以降の最初のフェンス開始行が言語タグなし（```のみ）なら行番号を返す */
function findUntaggedFence(lines) {
  let fmEnd = 0;
  if (lines[0] === '---') {
    for (let i = 1; i < lines.length; i++) {
      if (/^---\s*$/.test(lines[i])) { fmEnd = i; break; }
    }
  }
  for (let i = fmEnd + 1; i < lines.length; i++) {
    const m = lines[i].match(/^```(\S*)\s*$/);
    if (m) return m[1] === '' ? i + 1 : -1;
  }
  return -1;
}

function blockText(lines, range) {
  if (!range) return '';
  return lines.slice(range[0] - 1, range[1]).join('\n');
}

function stripVal(v) {
  return String(v == null ? '' : v).replace(/\s+#.*$/, '').trim().replace(/^["']|["']$/g, '');
}

/** テンプレートプレースホルダ（{...}）を含む値は突合対象にしない */
function isPlaceholder(s) {
  return /[{}]/.test(s);
}

/** `- key: value` で始まるリスト項目群を {key: value} の配列にする簡易パーサー */
function parseListOfMaps(text) {
  const items = [];
  let cur = null;
  for (const raw of text.split('\n')) {
    const item = raw.match(/^\s*-\s+([^\s:]+):\s*(.*)$/);
    if (item) {
      cur = {};
      cur[item[1]] = stripVal(item[2]);
      items.push(cur);
      continue;
    }
    const field = raw.match(/^\s+([^\s:-][^:]*):\s*(.*)$/);
    if (field && cur) cur[field[1].trim()] = stripVal(field[2]);
  }
  return items;
}

/** 入出力ブロックから inputs / outputs / exceptions のサブリストを取り出す */
function parseIo(text) {
  const result = { inputs: [], outputs: [], exceptions: [] };
  const lines = text.split('\n');
  let section = null;
  let buf = [];
  const flush = () => {
    if (section) result[section] = parseListOfMaps(buf.join('\n'));
    buf = [];
  };
  for (const line of lines) {
    const m = line.match(/^\s{2}(inputs|outputs|exceptions):\s*$/);
    if (m) {
      flush();
      section = m[1];
      continue;
    }
    if (section) buf.push(line);
  }
  flush();
  return result;
}

function parseConstants(text) {
  const consts = [];
  for (const raw of text.split('\n').slice(1)) {
    const m = raw.match(/^\s{2,}([A-Za-z0-9_]+):\s*(.+)$/);
    if (m) {
      consts.push({
        name: m[1],
        value: stripVal(m[2]),
        // `# drift-ok: <経路>` 付きの定数は drift 突合をスキップ（config/env 経由の正当な間接参照）
        driftOk: /#\s*drift-ok\b/.test(raw),
      });
    }
  }
  return consts;
}

/** 公開IF ブロックのスカラーフィールドを取り出す */
function parsePublicIf(text) {
  const get = (key) => {
    const m = text.match(new RegExp(`^\\s{2}${key}:\\s*(.+)$`, 'm'));
    return m ? stripVal(m[1]) : null;
  };
  return { protocol: get('protocol'), method: get('method'), path: get('path') };
}

function parseCovers(raw) {
  if (!raw) return [];
  return raw.replace(/[\[\]]/g, '').split(',').map(s => s.trim()).filter(Boolean);
}

/** 概要ブロックの satisfies: [REQ-XX, ...] を取り出す */
function parseSatisfies(overviewText) {
  const m = overviewText.match(/satisfies:\s*\[([^\]]*)\]/);
  if (!m) return [];
  return m[1].split(',').map(s => s.trim()).filter(s => /^REQ-\d{2,3}$/.test(s));
}

/** lint / drift / render で共有する仕様データを一度だけ組み立てる */
function parseSpecData(lines, spec) {
  const overviewText = blockText(lines, spec.blocks['概要']);
  const ioText = blockText(lines, spec.blocks['入出力']);
  const ifText = blockText(lines, spec.blocks['公開IF']);
  const flowText = blockText(lines, spec.blocks['フロー']);
  const testText = blockText(lines, spec.blocks['テスト仕様']);
  const nfText = blockText(lines, spec.blocks['非機能']);
  return {
    overviewText, ioText, ifText, flowText, testText, nfText,
    refText: [ioText, ifText, flowText, testText, nfText].join('\n'),
    consts: parseConstants(blockText(lines, spec.blocks['定数'])),
    io: parseIo(ioText),
    tests: parseListOfMaps(testText),
    publicIf: ifText ? parsePublicIf(ifText) : null,
    satisfies: parseSatisfies(overviewText),
  };
}

// ── graph.json I/O とノード解決 ─────────────────────────────────────────────

function fail(tool, msg) {
  console.error(`${tool}: ${msg}`);
  process.exit(1);
}

function runScan() {
  try {
    execFileSync(process.execPath, [SCAN_SCRIPT], { stdio: ['ignore', 'ignore', 'inherit'] });
  } catch {
    // missing_maps_to の exit 1 でも graph.json 自体は生成されている
  }
}

function loadGraph(tool) {
  if (!fs.existsSync(GRAPH_FILE)) runScan();
  if (!fs.existsSync(GRAPH_FILE)) fail(tool, `graph.json を生成できない（${path.relative(ROOT, GRAPH_FILE)}）`);
  return JSON.parse(fs.readFileSync(GRAPH_FILE, 'utf8'));
}

/**
 * target（node_id / docs パス / src・tests パス）からノードを特定する。
 * maps_to 逆引きが複数ヒットしたら候補を提示して exit 1。
 */
function resolveNode(tool, graph, target) {
  if (graph.nodes[target]) return { id: target, node: graph.nodes[target] };

  const rel = path.relative(ROOT, path.resolve(ROOT, target));
  const byFile = Object.entries(graph.nodes).find(([, n]) => n.file === rel);
  if (byFile) return { id: byFile[0], node: byFile[1] };

  const byMaps = Object.entries(graph.nodes).filter(([, n]) => (n.maps_to || []).includes(rel));
  if (byMaps.length === 1) return { id: byMaps[0][0], node: byMaps[0][1] };
  if (byMaps.length > 1) {
    fail(tool, `「${target}」は複数ノードに対応する。node_id で指定する:\n  ${byMaps.map(([id]) => id).join('\n  ')}`);
  }
  fail(tool, `「${target}」に対応するノードが見つからない（node_id / docs パス / maps_to 登録済みパスで指定する）`);
}

module.exports = {
  ROOT, DOCS_DIR, TOOL_DIR, GRAPH_FILE,
  findMdFiles, collectFiles,
  parseSpecRunnerFrontmatter, parseYamlList,
  parseSpecBlocks, findUntaggedFence, blockText, stripVal, isPlaceholder,
  parseListOfMaps, parseIo, parseConstants, parsePublicIf, parseCovers, parseSatisfies, parseSpecData,
  fail, runScan, loadGraph, resolveNode,
};
