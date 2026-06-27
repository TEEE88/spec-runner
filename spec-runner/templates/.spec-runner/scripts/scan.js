#!/usr/bin/env node
'use strict';

/**
 * spec-runner scan
 *
 * docs/**\/*.md の frontmatter（spec_runner:）を静的解析し、依存グラフを
 * <agent-dir>/.spec-runner/scan/graph.json にキャッシュする。
 *
 * 検証（全て警告。maps_to 欠落のみ exit 1。--strict 時は警告も exit 1）:
 *   lint      — 仕様内整合
 *               missing-block / block-order / unknown-block
 *               dead-constant / inline-value / dead-input
 *               uncovered-exception / unknown-exception-ref
 *               test-id-format / test-id-duplicate / ambiguous-wording / untagged-fence
 *               method-status-mismatch（GET/POST/PUT/PATCH/DELETE の成功ステータス）
 *               undefined-state（状態遷移の from/to が状態一覧に未定義）
 *               dead-depends_on（存在しない node_id への参照）
 *               duplicate-maps_to（複数ノードが同一ファイルを maps_to）
 *               cycle-depends_on（循環依存）
 *               uncovered-requirement / unknown-requirement-ref（REQ トレーサビリティ）
 *               uncovered-uc（業務ロジック概要の UC 一覧に node_id があるが詳細設計が存在しない）
 *               uncovered-screen（画面一覧の SCR 一覧に node_id があるが詳細設計が存在しない）
 *   drift     — 仕様⇔実装の文字列突合（maps_to 先コードを読む）
 *               constant-drift / endpoint-drift / exception-drift / input-drift / test-drift（双方向）
 *               policy-drift（エラーポリシーとの例外型↔ステータスコード突合）
 *   unmapped  — どの maps_to にも属さない src/tests ファイル（仕様なきコード）
 *
 * 使い方: node scan.js [--strict]
 */

const fs = require('fs');
const path = require('path');
const lib = require('./lib.js');

const { ROOT } = lib;
const OUTPUT_DIR = path.join(lib.TOOL_DIR, 'scan');

/** ファイルパスから kind を導出する（frontmatter の kind 廃止） */
function deriveKind(relPath) {
  const p = relPath.replace(/\\/g, '/');
  if (/^docs\/01_/.test(p)) return 'requirement';
  if (/^docs\/02_/.test(p)) return 'overview_design';
  if (/^docs\/03_[^/]*\/[^/]*\/00_[^/]*\//.test(p)) return 'common_policy';
  if (/^docs\/03_/.test(p)) return 'detailed_design';
  return null;
}

// 仕様YAMLの正規ブロック順。概要・入出力・テスト仕様以外は任意ブロック
const BLOCK_ORDER = ['概要', '定数', '公開IF', '入出力', '状態', 'フロー', '非機能', 'テスト仕様', '補足'];
const REQUIRED_BLOCKS = ['概要', '入出力', 'テスト仕様'];

// 曖昧語（LLM が勝手に解釈してブレる語）。「など/等」は語境界つき
const AMBIGUOUS_WORDS = /適切に|必要に応じて|柔軟に|できるだけ|なるべく|よしなに|いい感じ|場合によっては|など[、。)\s]|など$|等[、。)\s]|等$/;

// unmapped 検出の対象ルートと除外パターン
const UNMAPPED_ROOTS = ['src', 'tests', 'backend/src', 'backend/tests', 'frontend/src', 'frontend/tests'];
const UNMAPPED_IGNORE = ['node_modules', '__pycache__', '.venv', 'dist/', 'build/', '.next', 'coverage', 'fixtures', '__init__.py', 'conftest.py', '.d.ts', '.map'];

// ── 検証1: 仕様 lint（ファイル内部の整合） ──────────────────────────────────

function lintSpec(relPath, spec, data, lines) {
  const warnings = [];
  const warn = (rule, message) => warnings.push({ file: relPath, rule, message });

  const present = spec.order;

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
      const covers = lib.parseCovers(t.covers).map(c => c.replace(/^exceptions\./, ''));
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

  // 公開IF: method と成功ステータスの整合
  if (data.publicIf && data.ifText) {
    const rawMethod = data.publicIf.method || '';
    const methodUpper = rawMethod.toUpperCase().replace(/[^A-Z]/g, '');
    const successMatch = data.ifText.match(/^\s{2}成功:\s*(\d{3})/m);
    const successStatus = successMatch ? successMatch[1] : null;
    if (methodUpper && successStatus && !lib.isPlaceholder(rawMethod) && !lib.isPlaceholder(successStatus)) {
      const METHOD_VALID = { GET: ['200'], POST: ['200', '201'], PUT: ['200', '204'], PATCH: ['200', '204'], DELETE: ['200', '204'] };
      const valid = METHOD_VALID[methodUpper];
      if (valid && !valid.includes(successStatus)) {
        warn('method-status-mismatch', `公開IF: ${methodUpper} の成功ステータス ${successStatus} は標準外（期待: ${valid.join(' / ')}）`);
      }
    }
  }

  // 状態遷移: 遷移の from/to が状態一覧に定義されているか
  const stateText = lib.blockText(lines, spec.blocks['状態']);
  if (stateText) {
    const listMatch = stateText.match(/状態一覧:\s*\[([^\]]+)\]/);
    if (listMatch) {
      const defined = new Set(listMatch[1].split(',').map(s => s.trim()));
      const seen = new Set();
      for (const m of stateText.matchAll(/\{\s*from:\s*([^,}]+),\s*to:\s*([^,}]+),/g)) {
        for (const state of [m[1].trim(), m[2].trim()]) {
          if (!defined.has(state) && !seen.has(state)) {
            warn('undefined-state', `状態遷移の「${state}」が状態一覧に定義されていない`);
            seen.add(state);
          }
        }
      }
    }
  }

  // 曖昧語: LLM が解釈でブレる表現を仕様に書かない
  const allRanges = Object.values(spec.blocks);
  const minLine = Math.min(...allRanges.map(r => r[0]));
  const maxLine = Math.max(...allRanges.map(r => r[1]));
  for (let i = minLine; i <= maxLine; i++) {
    const line = lines[i - 1];
    if (line === undefined || lib.isPlaceholder(line)) continue;
    const m = line.match(AMBIGUOUS_WORDS);
    if (m) {
      warn('ambiguous-wording', `${i}行目に曖昧語「${m[0].trim().replace(/[、。)\s]$/, '')}」（条件・範囲を具体化する）`);
    }
  }

  return warnings;
}

// ── 検証2: drift（仕様⇔実装の文字列突合） ──────────────────────────────────

/**
 * maps_to 先のコードを読み、仕様に宣言された値が実装に現れるかを突合する。
 * 文字列で機械判定できる項目のみ。意味論（フロー順序・tx・ステータス集中マッピング）は LLM レビュー。
 */
function driftSpec(relPath, data, mapsTo) {
  const warnings = [];
  const warn = (rule, message) => warnings.push({ file: relPath, rule, message });

  let srcText = '';
  let testText = '';
  for (const mapped of mapsTo) {
    const files = lib.collectFiles(path.join(ROOT, mapped));
    const text = files.map(f => {
      try { return fs.readFileSync(f, 'utf8'); } catch { return ''; }
    }).join('\n');
    if (/(^|\/)tests?\//.test(mapped)) testText += text + '\n';
    else srcText += text + '\n';
  }
  if (srcText === '' && testText === '') return warnings; // 実装前は突合しない

  if (srcText !== '') {
    for (const c of data.consts) {
      if (c.driftOk || lib.isPlaceholder(c.name) || lib.isPlaceholder(c.value)) continue;
      if (!srcText.includes(c.name) && !(c.value.length >= 3 && srcText.includes(c.value))) {
        warn('constant-drift', `定数 ${c.name}（値 ${c.value}）が maps_to の実装に現れない（意図的な間接参照なら # drift-ok: <経路> を付ける）`);
      }
    }

    if (data.publicIf) {
      const { method, path: ifPath } = data.publicIf;
      if (ifPath && ifPath.startsWith('/') && !lib.isPlaceholder(ifPath) && !srcText.includes(ifPath)) {
        warn('endpoint-drift', `公開IF の path「${ifPath}」が maps_to の実装に現れない（Router 未配線の可能性）`);
      }
      if (method && !lib.isPlaceholder(method) && !new RegExp(method, 'i').test(srcText)) {
        warn('endpoint-drift', `公開IF の method「${method}」が maps_to の実装に現れない`);
      }
    }

    for (const ex of data.io.exceptions) {
      if (!ex.type || lib.isPlaceholder(ex.type)) continue;
      if (!srcText.includes(ex.type)) {
        warn('exception-drift', `例外型 ${ex.type} が maps_to の実装に現れない`);
      }
    }

    for (const input of data.io.inputs) {
      if (!input.name || lib.isPlaceholder(input.name)) continue;
      if (!srcText.includes(input.name)) {
        warn('input-drift', `input「${input.name}」が maps_to の実装に現れない`);
      }
    }
  }

  // T-XX: 仕様⇔テストコードの双方向突合
  if (testText !== '') {
    const specIds = new Set(data.tests.map(t => t.id).filter(id => id && /^T-\d{2,3}$/.test(id)));
    const implIds = new Set();
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

// ── 検証3: 要件定義からの REQ 抽出 ──────────────────────────────────────────

/** 要件定義から REQ-XX を抽出する。yaml フェンスの 受け入れ基準 ブロックを優先し、なければ旧 markdown 形式にフォールバック */
function parseRequirements(relPath, lines, spec) {
  const reqs = {};
  if (spec && spec.blocks['機能要件']) {
    const text = lib.blockText(lines, spec.blocks['機能要件']);
    for (const item of lib.parseListOfMaps(text)) {
      if (!item.id || !/^REQ-\d{2,3}$/.test(item.id)) continue;
      const content = item['内容'] || '';
      if (lib.isPlaceholder(content)) continue;
      reqs[item.id] = { file: relPath, text: content.trim(), satisfied_by: [] };
    }
    return reqs;
  }
  // 旧 markdown 形式: `- REQ-XX: <本文>`
  const content = lines.join('\n');
  for (const m of content.matchAll(/^\s*[-*]?\s*(REQ-\d{2,3})[:：]\s*(.+)$/gm)) {
    if (lib.isPlaceholder(m[2])) continue;
    reqs[m[1]] = { file: relPath, text: m[2].trim(), satisfied_by: [] };
  }
  return reqs;
}

// ── 検証3b: policy-drift（エラーポリシー ⇔ UC 公開IF のステータスコード突合） ──

/** エラーポリシーの ステータスコードマッピング ブロックを { 例外型: "ステータスコード" } に変換 */
function parseErrorPolicy(lines, spec) {
  if (!spec || !spec.blocks['ステータスコードマッピング']) return {};
  const [s, e] = spec.blocks['ステータスコードマッピング'];
  const text = lines.slice(s - 1, e).join('\n');
  const policy = {};
  for (const item of lib.parseListOfMaps(text)) {
    if (item.exception && item.status) policy[item.exception] = String(item.status);
  }
  return policy;
}

/** UC の 公開IF.エラー と errorPolicy を突合して policy-drift を返す */
function checkPolicyDrift(relPath, data, errorPolicy) {
  const warnings = [];
  if (!data.ifText || Object.keys(errorPolicy).length === 0) return warnings;
  for (const m of data.ifText.matchAll(/^\s*-\s*exceptions\.([^->\n]+?)\s*->\s*(\d{3})/gm)) {
    const cond = m[1].trim();
    const ucStatus = m[2];
    const ex = data.io.exceptions.find(e => e.cond && (e.cond.includes(cond) || cond.includes(e.cond)));
    if (!ex || !ex.type || lib.isPlaceholder(ex.type)) continue;
    const policyStatus = errorPolicy[ex.type];
    if (policyStatus && policyStatus !== ucStatus) {
      warnings.push({ file: relPath, rule: 'policy-drift',
        message: `例外型 ${ex.type} のステータスコードがエラーポリシー（${policyStatus}）と一致しない（公開IF: ${ucStatus}）` });
    }
  }
  return warnings;
}

// ── 検証4: unmapped（仕様なきコード） ───────────────────────────────────────

function findUnmapped(allMapsTo) {
  const fileSet = new Set();
  const dirPrefixes = [];
  for (const mapped of allMapsTo) {
    const abs = path.join(ROOT, mapped);
    if (mapped.endsWith('/') || (fs.existsSync(abs) && fs.statSync(abs).isDirectory())) {
      dirPrefixes.push(mapped.replace(/\/$/, '') + '/');
    } else {
      fileSet.add(mapped);
    }
  }

  const unmapped = [];
  for (const root of UNMAPPED_ROOTS) {
    for (const abs of lib.collectFiles(path.join(ROOT, root))) {
      const rel = path.relative(ROOT, abs);
      if (UNMAPPED_IGNORE.some(p => rel.includes(p))) continue;
      if (fileSet.has(rel)) continue;
      if (dirPrefixes.some(d => rel.startsWith(d))) continue;
      unmapped.push(rel);
    }
  }
  return unmapped;
}

// ── メイン ──────────────────────────────────────────────────────────────────

function main() {
  const strict = process.argv.includes('--strict');
  const files = lib.findMdFiles(lib.DOCS_DIR);

  const graph = {
    generated_at: new Date().toISOString(),
    nodes: {},          // node_id → { file, kind, depends_on, maps_to, blocks, satisfies }
    reverse_index: {},  // node_id → [依存元 node_id]
    requirements: {},   // REQ-XX → { file, text, satisfied_by }
    error_policy: {},   // 例外型 → ステータスコード（エラーポリシーから）
    missing_maps_to: [],
    lint: [],
    drift: [],
    unmapped: [],       // どの maps_to にも属さない src/tests ファイル
  };

  const allMapsTo = [];
  const nodeDataCache = {};  // policy-drift の2パス目用（node_id → { data, relPath }）
  const overviewUcEntries = [];     // uncovered-uc 用（業務ロジック概要から収集）
  const overviewScreenEntries = []; // uncovered-screen 用（画面一覧から収集）

  for (const file of files) {
    let content;
    try {
      content = fs.readFileSync(file, 'utf8');
    } catch {
      continue;
    }

    const fm = lib.parseSpecRunnerFrontmatter(content);
    if (!fm) continue;

    const relPath = path.relative(ROOT, file);
    const { node_id, depends_on, maps_to } = fm;
    const kind = deriveKind(relPath);
    const lines = content.split('\n');

    const spec = lib.parseSpecBlocks(lines);

    // 要件定義系から REQ-XX を収集（yaml フェンスの 受け入れ基準 ブロックを優先）
    if (kind && /^require/.test(kind)) {
      Object.assign(graph.requirements, parseRequirements(relPath, lines, spec));
    }
    let satisfies = [];
    if (spec) {
      const data = lib.parseSpecData(lines, spec);
      satisfies = data.satisfies;
      nodeDataCache[node_id] = { data, relPath };
      if (kind === 'overview_design') {
        // ユースケース一覧 / 画面一覧 の node_id を収集（uncovered-uc / uncovered-screen 用）
        const ucText = lib.blockText(lines, spec.blocks['ユースケース一覧']);
        if (ucText) {
          for (const item of lib.parseListOfMaps(ucText)) {
            if (item['名前'] && !lib.isPlaceholder(item['名前'])) {
              overviewUcEntries.push({ file: relPath, node_id: `詳細.ユースケース.${item['名前']}`, id: item.id || '' });
            }
          }
        }
        const screenText = lib.blockText(lines, spec.blocks['画面一覧']);
        if (screenText) {
          for (const item of lib.parseListOfMaps(screenText)) {
            if (item['名前'] && !lib.isPlaceholder(item['名前'])) {
              overviewScreenEntries.push({ file: relPath, node_id: `詳細.画面.${item['名前']}`, id: item.id || '' });
            }
          }
        }
      } else if (kind === 'detailed_design') {
        graph.lint.push(...lintSpec(relPath, spec, data, lines));
        graph.drift.push(...driftSpec(relPath, data, maps_to));
      }
      // common_policy / requirement / null → lint/drift スキップ
    } else if (kind === 'detailed_design') {
      const ln = lib.findUntaggedFence(lines);
      if (ln > 0) {
        graph.lint.push({ file: relPath, rule: 'untagged-fence', message: `${ln}行目のフェンスに言語タグがない（\`\`\`yaml にする。タグなしは仕様として検証されない）` });
      }
    }

    graph.nodes[node_id] = {
      file: relPath,
      depends_on,
      maps_to,
      blocks: spec ? spec.blocks : null,
      satisfies,
    };

    for (const dep of depends_on) {
      if (!graph.reverse_index[dep]) graph.reverse_index[dep] = [];
      graph.reverse_index[dep].push(node_id);
    }

    for (const mapped of maps_to) {
      allMapsTo.push(mapped);
      if (!fs.existsSync(path.join(ROOT, mapped))) {
        graph.missing_maps_to.push({ source: relPath, node_id, missing: mapped });
      }
    }
  }

  // 要件トレーサビリティ: satisfies の逆引きと未カバー検出
  for (const [id, node] of Object.entries(graph.nodes)) {
    for (const req of node.satisfies || []) {
      if (graph.requirements[req]) {
        graph.requirements[req].satisfied_by.push(id);
      } else {
        graph.lint.push({ file: node.file, rule: 'unknown-requirement-ref', message: `satisfies の ${req} が要件定義に存在しない` });
      }
    }
  }
  for (const [req, info] of Object.entries(graph.requirements)) {
    if (info.satisfied_by.length === 0) {
      graph.lint.push({ file: info.file, rule: 'uncovered-requirement', message: `${req}「${info.text}」を satisfies で引き受ける設計書がない（実装漏れの可能性）` });
    }
  }

  // dead-depends_on: depends_on に存在しない node_id を参照
  for (const [id, node] of Object.entries(graph.nodes)) {
    for (const dep of node.depends_on || []) {
      if (!graph.nodes[dep] && !lib.isPlaceholder(dep)) {
        graph.lint.push({ file: node.file, rule: 'dead-depends_on',
          message: `depends_on「${dep}」に対応するノードが存在しない` });
      }
    }
  }

  // duplicate-maps_to: 複数ノードが同じファイルを maps_to（正本が曖昧）
  const mapsToIndex = {};
  for (const [id, node] of Object.entries(graph.nodes)) {
    for (const m of node.maps_to || []) {
      if (!mapsToIndex[m]) mapsToIndex[m] = [];
      mapsToIndex[m].push(id);
    }
  }
  for (const [mapped, owners] of Object.entries(mapsToIndex)) {
    if (owners.length > 1) {
      for (const id of owners) {
        graph.lint.push({ file: graph.nodes[id].file, rule: 'duplicate-maps_to',
          message: `${mapped} が複数ノード（${owners.join(', ')}）から maps_to されている（正本が曖昧）` });
      }
    }
  }

  // cycle-depends_on: 循環依存の検出（DFS）
  {
    const fullyVisited = new Set();
    const inStack = new Set();
    const stackPath = [];
    const cycleWarns = [];
    function dfsCycle(id) {
      if (inStack.has(id)) {
        const start = stackPath.indexOf(id);
        cycleWarns.push({ file: graph.nodes[id]?.file || id, rule: 'cycle-depends_on',
          message: `循環依存: ${stackPath.slice(start).concat(id).join(' → ')}` });
        return;
      }
      if (fullyVisited.has(id)) return;
      inStack.add(id); stackPath.push(id);
      for (const dep of graph.nodes[id]?.depends_on || []) {
        if (graph.nodes[dep]) dfsCycle(dep);
      }
      stackPath.pop(); inStack.delete(id); fullyVisited.add(id);
    }
    for (const id of Object.keys(graph.nodes)) dfsCycle(id);
    graph.lint.push(...cycleWarns);
  }

  // uncovered-uc: 業務ロジック概要に列挙した UC の詳細設計が存在しない
  for (const entry of overviewUcEntries) {
    if (!graph.nodes[entry.node_id]) {
      graph.lint.push({ file: entry.file, rule: 'uncovered-uc',
        message: `${entry.id ? entry.id + ' ' : ''}node_id「${entry.node_id}」の詳細設計が存在しない（UC 設計書未作成の可能性）` });
    }
  }

  // uncovered-screen: 画面一覧に列挙した画面の詳細設計が存在しない
  for (const entry of overviewScreenEntries) {
    if (!graph.nodes[entry.node_id]) {
      graph.lint.push({ file: entry.file, rule: 'uncovered-screen',
        message: `${entry.id ? entry.id + ' ' : ''}node_id「${entry.node_id}」の詳細設計が存在しない（画面設計書未作成の可能性）` });
    }
  }

  // policy-drift: エラーポリシーが存在すれば全 UC と突合する
  const policyEntry = Object.entries(graph.nodes).find(([, n]) => n.kind === 'common_policy');
  if (policyEntry) {
    const policyAbs = path.join(ROOT, policyEntry[1].file);
    if (fs.existsSync(policyAbs)) {
      const policyLines = fs.readFileSync(policyAbs, 'utf8').split('\n');
      const policySpec = lib.parseSpecBlocks(policyLines);
      graph.error_policy = parseErrorPolicy(policyLines, policySpec);
      for (const { data, relPath: rp } of Object.values(nodeDataCache)) {
        graph.drift.push(...checkPolicyDrift(rp, data, graph.error_policy));
      }
    }
  }

  graph.unmapped = findUnmapped(allMapsTo);

  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  fs.writeFileSync(lib.GRAPH_FILE, JSON.stringify(graph, null, 2));

  if (graph.lint.length > 0) {
    console.warn(`spec lint: ${graph.lint.length} warning(s)`);
    for (const w of graph.lint) console.warn(`  LINT [${w.rule}] ${w.file}: ${w.message}`);
  }
  if (graph.drift.length > 0) {
    console.warn(`spec drift: ${graph.drift.length} warning(s)`);
    for (const w of graph.drift) console.warn(`  DRIFT [${w.rule}] ${w.file}: ${w.message}`);
  }
  if (graph.unmapped.length > 0) {
    console.warn(`unmapped: ${graph.unmapped.length} file(s) に対応する設計書がない（仕様なきコード）`);
    for (const f of graph.unmapped.slice(0, 20)) console.warn(`  UNMAPPED ${f}`);
    if (graph.unmapped.length > 20) console.warn(`  ... 他 ${graph.unmapped.length - 20} 件`);
  }

  const nodeCount = Object.keys(graph.nodes).length;
  const rel = path.relative(ROOT, lib.GRAPH_FILE);
  const counts = [];
  if (graph.lint.length > 0) counts.push(`lint: ${graph.lint.length}`);
  if (graph.drift.length > 0) counts.push(`drift: ${graph.drift.length}`);
  if (graph.unmapped.length > 0) counts.push(`unmapped: ${graph.unmapped.length}`);
  console.log(`spec-runner scan: ${nodeCount} nodes indexed → ${rel}${counts.length ? ` (${counts.join(', ')})` : ''}`);

  if (graph.missing_maps_to.length > 0) {
    console.warn(`\nmaps_to integrity: ${graph.missing_maps_to.length} missing reference(s)`);
    for (const m of graph.missing_maps_to) {
      console.warn(`  MISSING  ${m.missing}`);
      console.warn(`           in ${m.source} (${m.node_id})`);
    }
    process.exit(1);
  }
  if (strict && (graph.lint.length > 0 || graph.drift.length > 0 || graph.unmapped.length > 0)) {
    process.exit(1);
  }
}

main();
