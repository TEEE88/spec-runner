#!/usr/bin/env node
'use strict';

/**
 * spec-runner scan
 *
 * docs/**\/*.md の frontmatter（spec_runner: セクション）を静的解析し、
 * 依存グラフを <agent-dir>/.spec-runner/scan/graph.json にキャッシュする。
 *
 * 本文のハイブリッド仕様YAML（```yaml フェンス）に対して3つの検証を行う:
 *   1. ブロック行範囲の記録（extract.js が部分抽出に使う）
 *   2. lint  — 仕様ファイル内部の整合（死に定数・値の直書き・例外カバレッジ・T-XX 採番 等）
 *   3. drift — 仕様⇔実装の文字列突合（maps_to 先のコードを読み、定数値・公開IF・例外型・
 *              input 名・T-XX が実際に現れるかを機械検証する）
 *
 * lint / drift は警告（exit 0）。maps_to の参照先欠落のみ致命（exit 1）。
 * drift が警告に留まるのは、値が設定ファイル・環境変数経由になる正当な間接参照があるため。
 *
 * 出力:
 *   .claude/.spec-runner/scan/graph.json または .github/.spec-runner/scan/graph.json
 */

const fs = require('fs');
const path = require('path');

const ROOT = process.cwd();
const DOCS_DIR = path.join(ROOT, 'docs');
const TOOL_DIR = path.resolve(__dirname, '..');
const OUTPUT_DIR = path.join(TOOL_DIR, 'scan');
const OUTPUT_FILE = path.join(OUTPUT_DIR, 'graph.json');

// 仕様YAMLの正規ブロック順。概要・入出力・テスト仕様以外は任意ブロック
const BLOCK_ORDER = ['概要', '定数', '公開IF', '入出力', '状態', 'フロー', '非機能', 'テスト仕様', '補足'];
const REQUIRED_BLOCKS = ['概要', '入出力', 'テスト仕様'];

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
  // 注意: \s は改行を跨ぐため使わない（マルチライン配列の1件目が値側に食われる）
  const re = new RegExp(`^[ \\t]+${key}:[ \\t]*(.*)$`, 'm');
  const keyMatch = block.match(re);
  if (!keyMatch) return [];

  const inlineVal = keyMatch[1].trim();

  // インライン配列: [a, b, c]
  if (inlineVal.startsWith('[')) {
    return inlineVal.replace(/[\[\]]/g, '').split(',').map(s => s.trim()).filter(Boolean);
  }

  // マルチライン配列: - item
  const afterKey = block.slice(keyMatch.index + keyMatch[0].length);
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

// ── 仕様YAMLブロック解析 ────────────────────────────────────────────────────

/**
 * frontmatter 直後の最初の ```yaml フェンスを探し、トップレベルキーごとの
 * 行範囲（1始まり・両端含む）を返す。フェンスがなければ null。
 */
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
    if (m) consts.push({ name: m[1], value: stripVal(m[2]) });
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

/** lint / drift で共有する仕様データを一度だけ組み立てる */
function parseSpecData(lines, spec) {
  const ioText = blockText(lines, spec.blocks['入出力']);
  const ifText = blockText(lines, spec.blocks['公開IF']);
  const flowText = blockText(lines, spec.blocks['フロー']);
  const testText = blockText(lines, spec.blocks['テスト仕様']);
  const nfText = blockText(lines, spec.blocks['非機能']);
  return {
    ioText, ifText, flowText, testText, nfText,
    refText: [ioText, ifText, flowText, testText, nfText].join('\n'),
    consts: parseConstants(blockText(lines, spec.blocks['定数'])),
    io: parseIo(ioText),
    tests: parseListOfMaps(testText),
    publicIf: ifText ? parsePublicIf(ifText) : null,
  };
}

// ── 検証1: 仕様 lint（ファイル内部の整合） ──────────────────────────────────

function lintSpec(relPath, spec, data) {
  const warnings = [];
  const warn = (rule, message) => warnings.push({ file: relPath, rule, message });

  const present = spec.order;

  // ブロックの存在・順序・未知キー
  for (const b of REQUIRED_BLOCKS) {
    if (!present.includes(b)) warn('missing-block', `必須ブロック「${b}」がない`);
  }
  for (const b of present) {
    if (!BLOCK_ORDER.includes(b)) warn('unknown-block', `未知のブロック「${b}」（許可: ${BLOCK_ORDER.join(' / ')}）`);
  }
  const canonical = BLOCK_ORDER.filter(b => present.includes(b));
  const actual = present.filter(b => BLOCK_ORDER.includes(b));
  if (canonical.join(',') !== actual.join(',')) {
    warn('block-order', `ブロック順が正規順と異なる（正: ${canonical.join(' → ')}）`);
  }

  // 定数: 死に定数と値の直書き
  for (const c of data.consts) {
    if (!data.refText.includes(c.name)) {
      warn('dead-constant', `定数 ${c.name} がフロー・入出力・テスト仕様から参照されていない`);
    }
    if (c.value.length >= 4 && data.flowText.includes(c.value)) {
      warn('inline-value', `定数 ${c.name} の値「${c.value}」がフローに直書きされている（名前参照に置き換える）`);
    }
  }

  // 入出力: inputs の参照確認と exceptions のテストカバレッジ
  const flowAndTest = data.flowText + '\n' + data.testText;
  for (const input of data.io.inputs) {
    if (input.name && !flowAndTest.includes(input.name)) {
      warn('dead-input', `input「${input.name}」がフロー・テスト仕様から参照されていない`);
    }
  }

  for (const ex of data.io.exceptions) {
    if (!ex.type) continue;
    const covered = data.tests.some(t => {
      const covers = parseCovers(t.covers).map(c => c.replace(/^exceptions\./, ''));
      if (ex.cond && covers.some(c => ex.cond.includes(c) || c.includes(ex.cond))) return true;
      return ((t.case || '') + ' ' + (t.covers || '')).includes(ex.type);
    });
    if (!covered) {
      warn('uncovered-exception', `例外 ${ex.type}（${ex.cond || '条件未記載'}）を検証するテストがテスト仕様にない`);
    }
  }

  // 公開IF: エラー対応の参照先 exceptions が実在するか
  for (const m of data.ifText.matchAll(/-\s*exceptions\.([^\n]+?)\s*->/g)) {
    const ref = m[1].trim();
    const found = data.io.exceptions.some(ex => ex.cond && (ex.cond.includes(ref) || ref.includes(ex.cond)));
    if (!found) {
      warn('unknown-exception-ref', `公開IF のエラー対応「exceptions.${ref}」に一致する exceptions エントリがない`);
    }
  }

  // テスト仕様: T-XX の形式・重複
  const seen = new Set();
  for (const t of data.tests) {
    if (!t.id) continue;
    if (!/^T-\d{2,3}$/.test(t.id)) warn('test-id-format', `テストID「${t.id}」が T-XX 形式（2桁ゼロ埋め）でない`);
    if (seen.has(t.id)) warn('test-id-duplicate', `テストID「${t.id}」が重複している`);
    seen.add(t.id);
  }

  return warnings;
}

// ── 検証2: drift（仕様⇔実装の文字列突合） ──────────────────────────────────

/**
 * maps_to 先のコードを読み、仕様に宣言された値が実装に現れるかを突合する。
 * 文字列で機械判定できる項目だけを対象とし、意味論（フロー順序・tx 境界・
 * ステータスコードの集中マッピング等）は LLM レビューに委ねる。
 */
function driftSpec(relPath, data, mapsTo) {
  const warnings = [];
  const warn = (rule, message) => warnings.push({ file: relPath, rule, message });

  // maps_to をテスト系と実装系に分けて中身を読む
  let srcText = '';
  let testText = '';
  for (const mapped of mapsTo) {
    const files = collectFiles(path.join(ROOT, mapped));
    const text = files.map(f => {
      try { return fs.readFileSync(f, 'utf8'); } catch { return ''; }
    }).join('\n');
    if (/(^|\/)tests?\//.test(mapped)) testText += text + '\n';
    else srcText += text + '\n';
  }
  if (srcText === '' && testText === '') return warnings; // 実装前（red phase 以前）は突合しない

  // 定数: 名前または値が実装に現れるか
  if (srcText !== '') {
    for (const c of data.consts) {
      if (isPlaceholder(c.name) || isPlaceholder(c.value)) continue;
      if (!srcText.includes(c.name) && !(c.value.length >= 3 && srcText.includes(c.value))) {
        warn('constant-drift', `定数 ${c.name}（値 ${c.value}）が maps_to の実装に現れない`);
      }
    }

    // 公開IF: path と method が実装に現れるか
    if (data.publicIf) {
      const { method, path: ifPath } = data.publicIf;
      if (ifPath && ifPath.startsWith('/') && !isPlaceholder(ifPath) && !srcText.includes(ifPath)) {
        warn('endpoint-drift', `公開IF の path「${ifPath}」が maps_to の実装に現れない（Router 未配線の可能性）`);
      }
      if (method && !isPlaceholder(method) && !new RegExp(method, 'i').test(srcText)) {
        warn('endpoint-drift', `公開IF の method「${method}」が maps_to の実装に現れない`);
      }
    }

    // 例外型: 実装に現れるか
    for (const ex of data.io.exceptions) {
      if (!ex.type || isPlaceholder(ex.type)) continue;
      if (!srcText.includes(ex.type)) {
        warn('exception-drift', `例外型 ${ex.type} が maps_to の実装に現れない`);
      }
    }

    // input 名: 実装に現れるか（仕様駆動では引数名は仕様と一致させる）
    for (const input of data.io.inputs) {
      if (!input.name || isPlaceholder(input.name)) continue;
      if (!srcText.includes(input.name)) {
        warn('input-drift', `input「${input.name}」が maps_to の実装に現れない`);
      }
    }
  }

  // T-XX: 仕様⇔テストコードの双方向突合
  if (testText !== '') {
    const specIds = new Set(data.tests.map(t => t.id).filter(id => id && /^T-\d{2,3}$/.test(id)));
    const implIds = new Set();
    // テスト関数名では T_01 形式（- が _ に置換）になるため両形式を拾う
    // 前が英数字でなく（_T_01 は許容）、後ろに数字が続かない（T-1234 を除外）
    for (const m of testText.matchAll(/(?<![A-Za-z0-9])T[-_](\d{2,3})(?![0-9])/g)) implIds.add(`T-${m[1]}`);
    for (const id of specIds) {
      if (!implIds.has(id)) warn('test-drift', `テスト仕様 ${id} に対応するテストがテストコードに現れない`);
    }
    for (const id of implIds) {
      if (!specIds.has(id)) warn('test-drift', `テストコードの ${id} がテスト仕様に存在しない（仕様に追加するか削除する）`);
    }
  }

  return warnings;
}

// ── メイン ──────────────────────────────────────────────────────────────────

function main() {
  const files = findMdFiles(DOCS_DIR);

  const graph = {
    generated_at: new Date().toISOString(),
    nodes: {},         // node_id → { file, kind, depends_on, maps_to, blocks }
    reverse_index: {}, // node_id → [依存元 node_id のリスト]（影響範囲検索用）
    missing_maps_to: [], // { source, node_id, missing } 存在しないファイル参照
    lint: [],          // { file, rule, message } 仕様ファイル内部の警告
    drift: [],         // { file, rule, message } 仕様⇔実装の乖離警告
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
    const lines = content.split('\n');

    // 本文の仕様YAMLブロック（あれば行範囲を記録し lint / drift を行う）
    const spec = parseSpecBlocks(lines);
    graph.nodes[node_id] = {
      file: relPath,
      kind,
      depends_on,
      maps_to,
      blocks: spec ? spec.blocks : null,
    };
    if (spec) {
      const data = parseSpecData(lines, spec);
      graph.lint.push(...lintSpec(relPath, spec, data));
      graph.drift.push(...driftSpec(relPath, data, maps_to));
    } else if (kind === 'detailed_design') {
      // タグなしフェンスは仕様として認識されず lint / drift / 抽出から漏れる
      const ln = findUntaggedFence(lines);
      if (ln > 0) {
        graph.lint.push({ file: relPath, rule: 'untagged-fence', message: `${ln}行目のフェンスに言語タグがない（\`\`\`yaml にする。タグなしは仕様として検証されない）` });
      }
    }

    // リバースインデックスを構築（A が B に depends_on → reverse_index[B].push(A)）
    for (const dep of depends_on) {
      if (!graph.reverse_index[dep]) graph.reverse_index[dep] = [];
      graph.reverse_index[dep].push(node_id);
    }

    // maps_to の実在チェック
    for (const mapped of maps_to) {
      const mappedPath = path.join(ROOT, mapped);
      if (!fs.existsSync(mappedPath)) {
        graph.missing_maps_to.push({ source: relPath, node_id, missing: mapped });
      }
    }
  }

  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(graph, null, 2));

  if (graph.lint.length > 0) {
    console.warn(`spec lint: ${graph.lint.length} warning(s)`);
    for (const w of graph.lint) {
      console.warn(`  LINT [${w.rule}] ${w.file}: ${w.message}`);
    }
  }
  if (graph.drift.length > 0) {
    console.warn(`spec drift: ${graph.drift.length} warning(s)`);
    for (const w of graph.drift) {
      console.warn(`  DRIFT [${w.rule}] ${w.file}: ${w.message}`);
    }
  }

  const nodeCount = Object.keys(graph.nodes).length;
  const rel = path.relative(ROOT, OUTPUT_FILE);
  const counts = [];
  if (graph.lint.length > 0) counts.push(`lint: ${graph.lint.length}`);
  if (graph.drift.length > 0) counts.push(`drift: ${graph.drift.length}`);
  console.log(`spec-runner scan: ${nodeCount} nodes indexed → ${rel}${counts.length ? ` (${counts.join(', ')})` : ''}`);

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
