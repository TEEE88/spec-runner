#!/usr/bin/env node
// =============================================================================
// spec-runner — AI-driven DDD phase gate system installer
// =============================================================================
// npx spec-runner           → 開発環境のみ選択してファイル展開
// npx spec-runner --configure → パス・TDD等の詳細設定（対話）。init からも呼ばれる
// npx spec-runner --update  → 既存プロジェクトを最新版に更新
// =============================================================================

'use strict';

const path = require('path');
const fs   = require('fs');
const { execSync, spawnSync } = require('child_process');

// ── 依存チェック（chalk/enquirer/ora が入っていない場合のフォールバック） ──
let chalk, ora;
try {
  chalk = require('chalk');
} catch {
  // chalk がない場合のフォールバック（bold.green 等の連鎖にも対応）
  const id = s => s;
  const proxy = () => new Proxy(id, { get: () => proxy() });
  chalk = new Proxy(id, { get: () => proxy() });
}
try {
  ora = require('ora');
} catch {
  ora = (text) => ({ start: () => ({ succeed: (t) => console.log('✓', t || text), fail: (t) => console.error('✗', t || text) }) });
}

// ── 定数 ──────────────────────────────────────────────────────────────────────
const PKG_DIR    = path.resolve(__dirname, '..');
const PKG_JSON   = (() => { try { return require(path.join(PKG_DIR, 'package.json')); } catch { return {}; } })();
const VERSION    = PKG_JSON.version || '?.?.?';
const CWD        = process.cwd();
const CONFIG_DIR = path.join(CWD, '.spec-runner');
const CONFIG_SH  = path.join(CONFIG_DIR, 'config.sh');
const ARGS       = process.argv.slice(2);

const isUpdate       = ARGS.includes('--update');
const isConfigure    = ARGS.includes('--configure');
const isSkipQuestion = ARGS.includes('--skip-questions');
const isDryRun       = ARGS.includes('--dry-run');

// ── ユーティリティ ────────────────────────────────────────────────────────────
const log  = (...a) => console.log(...a);
const ok   = (msg) => log(chalk.green('✓'), msg);
const warn = (msg) => log(chalk.yellow('⚠'), msg);
const info = (msg) => log(chalk.cyan('ℹ'), msg);
const err  = (msg) => { console.error(chalk.red('ERROR:'), msg); process.exit(1); };

function checkCommand(cmd) {
  const r = spawnSync(cmd, ['--version'], { stdio: 'ignore' });
  return r.status === 0;
}

function copyFile(src, dest, vars = {}) {
  if (!fs.existsSync(src)) return;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  let content = fs.readFileSync(src, 'utf8');
  // テンプレート変数を置換 {{VAR}}
  for (const [k, v] of Object.entries(vars)) {
    content = content.replaceAll(`{{${k}}}`, v);
  }
  if (!isDryRun) fs.writeFileSync(dest, content);
  ok(`${path.relative(CWD, dest)}`);
}

function copyDir(srcDir, destDir, vars = {}) {
  if (!fs.existsSync(srcDir)) return;
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const srcPath  = path.join(srcDir, entry.name);
    const destPath = path.join(destDir, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath, vars);
    } else {
      if (!fs.existsSync(destPath)) {
        copyFile(srcPath, destPath, vars);
      } else {
        warn(`スキップ（既存）: ${path.relative(CWD, destPath)}`);
      }
    }
  }
}

// ── 対話型プロンプト（enquirer がない場合は readline フォールバック） ────────
async function prompt(questions) {
  try {
    const { prompt: enquirerPrompt } = require('enquirer');
    return await enquirerPrompt(questions);
  } catch {
    // readline フォールバック
    const readline = require('readline');
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const answers = {};
    for (const q of questions) {
      if (q.type === 'select') {
        const choices = q.choices.map((c, i) => `  ${i + 1}) ${(c && c.name) != null ? c.name : c}`).join('\n');
        const answer = await new Promise(resolve => {
          rl.question(`${q.message}\n${choices}\n番号を入力: `, resolve);
        });
        const idx = parseInt(answer, 10) - 1;
        const chosen = q.choices[idx] || q.choices[0];
        answers[q.name] = (chosen && chosen.value != null) ? chosen.value : chosen;
      } else if (q.type === 'multiselect') {
        const choiceList = q.choices.map((c, i) => `  ${i + 1}) ${c.name || c}`).join('\n');
        const answer = await new Promise(resolve => {
          rl.question(`${q.message}\n${choiceList}\n番号をカンマ区切りで入力（例: 1,2,3）。すべて選ぶ場合は Enter: `, resolve);
        });
        const selected = answer.trim() || q.choices.map((_, i) => i).join(',');
        const indices = selected.split(',').map(s => parseInt(s.trim(), 10) - 1).filter(i => i >= 0 && i < q.choices.length);
        answers[q.name] = indices.map(i => (q.choices[i] && q.choices[i].value) || q.choices[i]);
      } else if (q.type === 'confirm') {
        const answer = await new Promise(resolve => {
          rl.question(`${q.message} [y/N]: `, resolve);
        });
        answers[q.name] = /^[yY]/.test(answer);
      } else if (q.type === 'input') {
        const initial = (q.initial !== undefined && q.initial !== null) ? String(q.initial) : '';
        const answer = await new Promise(resolve => {
          rl.question(initial ? `${q.message} [${initial}]: ` : `${q.message}: `, resolve);
        });
        answers[q.name] = (answer && answer.trim()) || initial;
      } else {
        const answer = await new Promise(resolve => {
          rl.question(`${q.message}: `, resolve);
        });
        answers[q.name] = answer || (q.initial || '');
      }
    }
    rl.close();
    return answers;
  }
}

// ── 既定の構造（AI と相談した結果で上書きできる）────────────────────────────
const DEFAULT_STRUCTURE = {
  domainPath: 'src/domain',
  usecasePath: 'src/useCase',
  infraPath: 'src/infrastructure',
  migrationDir: '',
  sourceExtensions: 'ts tsx js jsx',
  domainForbiddenGrepPattern: '',
  testExtensions: 'test.ts test.tsx spec.ts spec.tsx',
  appSourceDir: 'src',
  testDir: 'tests',
  buildCmd: 'echo "build"',
  testCmd: 'echo "test"',
  lintCmd: 'echo "lint"',
};

// ── メイン処理 ────────────────────────────────────────────────────────────────
async function main() {
  log('');
  log(chalk.bold('╔════════════════════════════════════════╗'));
  const verPad = Math.max(0, 17 - String(VERSION).length);
  log(chalk.bold(`║     spec-runner  v${VERSION}${' '.repeat(verPad)}║`));
  log(chalk.bold('║  AI-driven DDD Phase Gate System       ║'));
  log(chalk.bold('╚════════════════════════════════════════╝'));
  log('');

  // ── 依存チェック ──────────────────────────────────────────────────────────
  if (!checkCommand('jq')) {
    err('jq がインストールされていません。\n  macOS: brew install jq\n  Ubuntu: sudo apt install jq');
  }
  if (!checkCommand('git')) {
    err('git がインストールされていません。');
  }
  ok('依存チェック完了 (jq, git)');
  log('');

  // ── 更新モード ──────────────────────────────────────────────────────────────
  if (isUpdate) {
    await runUpdate();
    return;
  }

  // ── 設定モード（init から呼ばれる。詳細対話で config を更新）────────────────
  if (isConfigure) {
    await runConfigure();
    return;
  }

  // ── 既存の spec-runner チェック ─────────────────────────────────────────────
  if (fs.existsSync(CONFIG_SH)) {
    warn('既に spec-runner が導入されています。');
    info('更新するには: npx spec-runner --update');
    info('再設定するには: ./.spec-runner/scripts/spec-runner.sh init（対話でパス等を設定）');
    process.exit(0);
  }

  // ── 初回セットアップ：開発環境のみ選択 ─────────────────────────────────────
  const d = DEFAULT_STRUCTURE;
  let answers;
  if (isSkipQuestion) {
    answers = {
      tools: ['claude', 'cursor', 'copilot'],
      ci: 'github-actions',
      language: 'ja',
    };
  } else {
    log('');
    info(chalk.bold('どの開発環境で使いますか？'));
    log('');
    answers = await prompt([
      {
        type: 'select',
        name: 'tools',
        message: 'どの AI ツール用の設定をインストールしますか？（矢印で移動・Enter で確定）',
        choices: [
          { name: 'Claude Code', value: 'claude' },
          { name: 'Cursor', value: 'cursor' },
          { name: 'GitHub Copilot', value: 'copilot' },
        ],
      },
      {
        type: 'select',
        name: 'ci',
        message: 'CI/CD プラットフォームを選択してください',
        choices: ['github-actions', 'gitlab-ci', 'none'],
      },
      {
        type: 'select',
        name: 'language',
        message: 'ドキュメントの言語を選択してください',
        choices: ['ja', 'en'],
      },
    ]);
  }
  // 詳細設定は init 時の対話に回す。ここでは既定値を使用
  answers = {
    ...answers,
    runtimeMemo: '',
    projectNote: '',
    domainPath: d.domainPath,
    usecasePath: d.usecasePath,
    infraPath: d.infraPath,
    migrationDir: d.migrationDir,
    sourceExtensions: d.sourceExtensions,
    domainForbiddenGrepPattern: d.domainForbiddenGrepPattern,
    testDir: d.testDir,
    ddd: true,
    tdd: true,
  };

  // Select は単一値で返るので配列に統一。name で返る場合もあるので value に正規化
  const toolValueMap = { 'claude code': 'claude', 'cursor': 'cursor', 'github copilot': 'copilot' };
  const raw = answers.tools;
  const toolsArr = Array.isArray(raw) ? raw : (raw ? [raw] : []);
  answers.tools = toolsArr.map((t) => {
    const s = (typeof t === 'string' ? t : '').toLowerCase();
    return toolValueMap[s] || s || null;
  }).filter(Boolean);
  if (answers.tools.length === 0) {
    answers.tools = ['claude', 'cursor', 'copilot'];
  }

  const toolLabels = { claude: 'Claude Code', cursor: 'Cursor', copilot: 'GitHub Copilot' };
  log('');
  info(`構造: ${chalk.cyan(answers.domainPath)} → ${chalk.cyan(answers.usecasePath)} → ${chalk.cyan(answers.infraPath)}`);
  info(`ツール: ${chalk.cyan((answers.tools || []).map(t => toolLabels[t] || t).join(', '))}`);
  info(`DDD: ${chalk.cyan(answers.ddd ? 'あり' : 'なし')} / TDD: ${chalk.cyan(answers.tdd !== false ? '必須' : 'オプション')} / CI: ${chalk.cyan(answers.ci)} / 言語: ${chalk.cyan(answers.language)}`);
  log('');

  // ── ファイル展開 ──────────────────────────────────────────────────────────
  const spinner = ora('ファイルを展開中...').start();
  try {
    await deployFiles(answers);
    spinner.succeed('ファイルの展開完了');
  } catch (e) {
    spinner.fail('展開中にエラーが発生しました');
    err(e.message);
  }

  // ── 完了メッセージ ────────────────────────────────────────────────────────
  const tools = answers.tools || ['claude'];
  log('');
  log(chalk.bold.green('✅ spec-runner のセットアップが完了しました！'));
  log('');
  log(chalk.bold('次のステップ:'));
  log('  • まずプロジェクトの土台を書く（init の前に行う）:');
  log(chalk.cyan('    docs/01_憲章.md  … 不変原則・品質ルール（プロジェクト憲章）'));
  log(chalk.cyan('    docs/02_仕様.md  … 何を作るか・なぜか・スコープ（仕様）'));
  log('    チャットで /sr-憲章 または /sr-仕様 と入力すると編集を案内できます。');
  log('');
  log('  • パス・TDD 等の設定と最初のユースケース開始:');
  log(chalk.cyan('       ./.spec-runner/scripts/spec-runner.sh init "ユースケース名" "集約名"'));
  log('    またはチャットで: ' + chalk.cyan('/sr-初期化 ユースケース名 集約名'));
  log('');
  log('  init を実行すると対話で Domain/UseCase のパスやテスト設定を聞かれます。');
  log('  引数なしで init だけ実行すると設定対話のみ行えます。');
  log('');
  if (tools.includes('claude')) {
    log('  • Claude Code: CLAUDE.md をプロジェクトルートに置いたまま開く');
  }
  if (tools.includes('cursor')) {
    log('  • Cursor: .cursorrules が読み込まれます。Rules for AI で確認してください');
  }
  if (tools.includes('copilot')) {
    log('  • GitHub Copilot: .github/copilot-instructions.md が参照されます');
  }
  log('');
  log(chalk.bold('コマンド一覧:'));
  log(chalk.cyan('  ./.spec-runner/scripts/spec-runner.sh help'));
  log('');
  log(chalk.gray('💡 構造を変えたいときは .spec-runner/config.sh を編集してください'));
}

// ── ファイル展開処理 ──────────────────────────────────────────────────────────
function dddLayerPatternFromPaths(domainPath, usecasePath, infraPath) {
  const last = (p) => (p || '').split('/').filter(Boolean).pop() || '';
  return [last(domainPath), last(usecasePath), last(infraPath)].filter(Boolean).join('|') || 'domain|useCase|infrastructure';
}

async function deployFiles(answers) {
  const d = DEFAULT_STRUCTURE;
  const domainPath   = (answers.domainPath || d.domainPath).trim();
  const usecasePath  = (answers.usecasePath || d.usecasePath).trim();
  const infraPath    = (answers.infraPath || d.infraPath).trim();
  const migrationDir = (answers.migrationDir || d.migrationDir).trim();
  const sourceExt    = (answers.sourceExtensions || d.sourceExtensions).trim();
  const forbiddenPat = (answers.domainForbiddenGrepPattern || d.domainForbiddenGrepPattern).trim();
  const testDir      = (answers.testDir || d.testDir).trim() || 'tests';

  const toolsList = (answers.tools || ['claude']).join(',');
  const vars = {
    FRAMEWORK:                 'custom',
    SPEC_RUNNER_TOOLS:         toolsList,
    RUNTIME_MEMO:              (answers.runtimeMemo || '').trim().replace(/\s+/g, ' '),
    LANGUAGE:                  answers.language || 'ja',
    DDD_ENABLED:               answers.ddd ? 'true' : 'false',
    TDD_ENABLED:               answers.tdd !== false ? 'true' : 'false',
    SOURCE_EXTENSIONS:         sourceExt,
    TEST_EXTENSIONS:           d.testExtensions,
    APP_SOURCE_DIR:            d.appSourceDir,
    TEST_DIR:                  testDir,
    MIGRATION_DIR:             migrationDir,
    BUILD_CMD:                 d.buildCmd,
    TEST_CMD:                  d.testCmd,
    LINT_CMD:                  d.lintCmd,
    DOMAIN_PATH:               domainPath,
    USECASE_PATH:              usecasePath,
    INFRA_PATH:                infraPath,
    DDD_LAYER_PATTERN:         dddLayerPatternFromPaths(domainPath, usecasePath, infraPath),
    DOMAIN_FORBIDDEN_GREP_PATTERN: forbiddenPat,
    CI_PLATFORM:               answers.ci || 'github-actions',
    DOC_LANGUAGE:              answers.language || 'ja',
    CONFIGURED:                answers.configured !== undefined ? (answers.configured ? 'true' : 'false') : 'false',
  };

  const templatesDir = path.join(PKG_DIR, 'templates');
  const baseDir   = path.join(templatesDir, 'base');
  const claudeDir = path.join(templatesDir, 'claude');
  const cursorDir = path.join(templatesDir, 'cursor');
  const copilotDir = path.join(templatesDir, 'copilot');
  const tools = answers.tools || ['claude'];

  function copyPathFrom(srcDir, relPath, destDir) {
    const src = path.join(srcDir, relPath);
    const dest = path.join(destDir || CWD, relPath);
    if (!fs.existsSync(src)) return;
    if (fs.statSync(src).isDirectory()) {
      copyDir(src, dest, vars);
    } else {
      copyFile(src, dest, vars);
    }
  }

  log('');
  log(chalk.bold('展開するファイル:'));

  // 1. 共通（base）: .spec-runner/ に scripts と templates をまとめて配置
  const specRunnerDir = path.join(CWD, '.spec-runner');
  copyPathFrom(baseDir, 'scripts', specRunnerDir);
  copyPathFrom(baseDir, 'templates', specRunnerDir);
  // .spec-runner/templates/初期ドキュメント/ の中身を docs/ に展開（憲章・仕様・用語集等）
  const docsInitialSrc = path.join(specRunnerDir, 'templates', '初期ドキュメント');
  const docsDest = path.join(CWD, 'docs');
  if (fs.existsSync(docsInitialSrc)) {
    copyDir(docsInitialSrc, docsDest, vars);
  }
  // 生成用テンプレートのうち設計判断記録ひな形は docs/99_設計判断記録/ にも置く（新規 ADR 作成時のコピー元）
  const adrTemplateSrc = path.join(specRunnerDir, 'templates', '99_設計判断記録', 'ひな形.md');
  const adrTemplateDest = path.join(CWD, 'docs', '99_設計判断記録', 'ひな形.md');
  if (fs.existsSync(adrTemplateSrc)) {
    fs.mkdirSync(path.dirname(adrTemplateDest), { recursive: true });
    if (!isDryRun) fs.copyFileSync(adrTemplateSrc, adrTemplateDest);
  }
  // CI で github-actions を選んだときだけ .github のワークフロー・PR テンプレートを配置
  if (answers.ci === 'github-actions') {
    copyPathFrom(baseDir, '.github/workflows');
    copyPathFrom(baseDir, '.github/PULL_REQUEST_TEMPLATE.md');
  }

  // 2. Claude Code 選択時: templates/claude/ をそのままコピー
  if (tools.includes('claude')) {
    copyDir(claudeDir, CWD, vars);
  }

  // 3. Cursor 選択時: templates/cursor/ をそのままコピー
  if (tools.includes('cursor')) {
    copyDir(cursorDir, CWD, vars);
  }

  // 4. Copilot 選択時: templates/copilot/.github/ を CWD/.github/ にマージ
  if (tools.includes('copilot')) {
    copyDir(path.join(copilotDir, '.github'), path.join(CWD, '.github'), vars);
  }

  // 5. .spec-runner/config.sh を生成
  generateConfigSh(vars);

  // 6. .gitignore に .spec-runner/state.json を追加
  appendGitignore();

  // 7. .spec-runner/scripts/spec-runner.sh に実行権限を付与
  const devShPath = path.join(specRunnerDir, 'scripts', 'spec-runner.sh');
  if (fs.existsSync(devShPath) && !isDryRun) {
    fs.chmodSync(devShPath, '755');
  }
  if (tools.includes('claude')) {
    const hookPath = path.join(CWD, '.claude', 'hooks', 'pre-tool-use.sh');
    if (fs.existsSync(hookPath) && !isDryRun) {
      fs.chmodSync(hookPath, '755');
    }
  }
}

// ── .spec-runner/config.sh 生成 ─────────────────────────────────────────────────
function generateConfigSh(vars) {
  const content = `# =============================================================================
# .spec-runner/config.sh — spec-runner 設定
# このファイルは .spec-runner/scripts/spec-runner.sh が読み込む設定ファイルです
# npx spec-runner / init 時の対話で生成・更新されます
# =============================================================================
# 詳細設定済みか（init で対話すると true になる）
export CONFIGURED="${vars.CONFIGURED || 'false'}"

# 使用フレームワーク・言語（相談で決定）: ${vars.RUNTIME_MEMO || '（未記入）'}

# フレームワーク情報
export SPEC_RUNNER_FRAMEWORK="${vars.FRAMEWORK}"
export SPEC_RUNNER_TOOLS="${vars.SPEC_RUNNER_TOOLS || 'claude,cursor,copilot'}"
export SPEC_RUNNER_LANGUAGE="${vars.LANGUAGE}"
export SPEC_RUNNER_DDD_ENABLED="${vars.DDD_ENABLED}"
export SPEC_RUNNER_DOC_LANGUAGE="${vars.DOC_LANGUAGE}"

# TDD（テスト駆動）: true のとき実装前にテスト設計＋テストコード必須。false でオプションに
export TDD_ENABLED="${vars.TDD_ENABLED}"

# ─────────────────────────────────────────────────────────────────────────────
# 拡張子設定
# フェーズゲートフックがブロック対象にする拡張子（スペース区切り）
# ─────────────────────────────────────────────────────────────────────────────
export SOURCE_EXTENSIONS="${vars.SOURCE_EXTENSIONS}"
export TEST_EXTENSIONS="${vars.TEST_EXTENSIONS}"

# ─────────────────────────────────────────────────────────────────────────────
# ディレクトリ構成
# ─────────────────────────────────────────────────────────────────────────────
export APP_SOURCE_DIR="${vars.APP_SOURCE_DIR}"
export TEST_DIR="${vars.TEST_DIR}"
export MIGRATION_DIR="${vars.MIGRATION_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
# DDD レイヤー設定
# CI の DDD 依存方向チェックで使用。空ならスキップ
# ─────────────────────────────────────────────────────────────────────────────
export DOMAIN_PATH="${vars.DOMAIN_PATH}"
export USECASE_PATH="${vars.USECASE_PATH}"
export INFRA_PATH="${vars.INFRA_PATH}"
export DDD_LAYER_PATTERN="${vars.DDD_LAYER_PATTERN}"
export DOMAIN_FORBIDDEN_GREP_PATTERN="${vars.DOMAIN_FORBIDDEN_GREP_PATTERN}"

# ─────────────────────────────────────────────────────────────────────────────
# ビルド / テスト コマンド
# ─────────────────────────────────────────────────────────────────────────────
export BUILD_CMD="${vars.BUILD_CMD}"
export TEST_CMD="${vars.TEST_CMD}"
export LINT_CMD="${vars.LINT_CMD}"

# ─────────────────────────────────────────────────────────────────────────────
# CI/CD 設定
# ─────────────────────────────────────────────────────────────────────────────
export CI_PLATFORM="${vars.CI_PLATFORM}"
`;

  const dest = CONFIG_SH;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  if (!isDryRun) fs.writeFileSync(dest, content);
  ok(`.spec-runner/config.sh`);
}

// ── .gitignore 更新 ───────────────────────────────────────────────────────────
function appendGitignore() {
  const gitignorePath = path.join(CWD, '.gitignore');
  const additions = [
    '',
    '# spec-runner state (作業中の状態ファイル)',
    '.spec-runner/state.json',
  ].join('\n');

  if (fs.existsSync(gitignorePath)) {
    const content = fs.readFileSync(gitignorePath, 'utf8');
    if (!content.includes('.spec-runner/state.json')) {
      if (!isDryRun) fs.appendFileSync(gitignorePath, additions);
      ok('.gitignore に .spec-runner/state.json を追加');
    }
  } else {
    if (!isDryRun) fs.writeFileSync(gitignorePath, additions.trimStart());
    ok('.gitignore を作成');
  }
}

// ── config.sh から変数をパース ─────────────────────────────────────────────────
function parseConfigSh(content) {
  const vars = {};
  const re = /^export\s+([A-Z_]+)="([^"]*)"\s*$/gm;
  let m;
  while ((m = re.exec(content)) !== null) {
    vars[m[1]] = m[2];
  }
  return vars;
}

// ── 設定モード（init から呼ばれる。詳細対話で config を更新）────────────────────
async function runConfigure() {
  if (!fs.existsSync(CONFIG_SH)) {
    err('.spec-runner/config.sh が見つかりません。まず npx spec-runner を実行してください。');
  }

  const d = DEFAULT_STRUCTURE;
  const configContent = fs.readFileSync(CONFIG_SH, 'utf8');
  const cfg = parseConfigSh(configContent);

  log('');
  log(chalk.bold('╔════════════════════════════════════════╗'));
  log(chalk.bold('║  spec-runner 詳細設定（パス・TDD 等）   ║'));
  log(chalk.bold('╚════════════════════════════════════════╝'));
  log('');
  info('AI と相談して決めた構造を入力してください。既定値でよければ Enter。');
  log('');

  const answers = await prompt([
    {
      type: 'input',
      name: 'runtimeMemo',
      message: '使用フレームワーク・言語（AI と相談した名前。任意）',
      initial: cfg.RUNTIME_MEMO || '',
    },
    {
      type: 'input',
      name: 'projectNote',
      message: 'やりたいこと・プロジェクトの種類（メモ用・任意）',
      initial: '',
    },
    {
      type: 'input',
      name: 'domainPath',
      message: 'Domain 層のパス',
      initial: cfg.DOMAIN_PATH || d.domainPath,
    },
    {
      type: 'input',
      name: 'usecasePath',
      message: 'UseCase 層のパス',
      initial: cfg.USECASE_PATH || d.usecasePath,
    },
    {
      type: 'input',
      name: 'infraPath',
      message: 'Infrastructure 層のパス',
      initial: cfg.INFRA_PATH || d.infraPath,
    },
    {
      type: 'input',
      name: 'migrationDir',
      message: 'マイグレーション等のディレクトリ（無ければ空で Enter）',
      initial: cfg.MIGRATION_DIR || d.migrationDir,
    },
    {
      type: 'input',
      name: 'sourceExtensions',
      message: 'ソースの拡張子（スペース区切り）',
      initial: cfg.SOURCE_EXTENSIONS || d.sourceExtensions,
    },
    {
      type: 'input',
      name: 'domainForbiddenGrepPattern',
      message: 'Domain が import してはいけないパターン（正規表現、空でスキップ）',
      initial: cfg.DOMAIN_FORBIDDEN_GREP_PATTERN || d.domainForbiddenGrepPattern,
    },
    {
      type: 'input',
      name: 'testDir',
      message: 'テストディレクトリのパス（TDD で未コミット検出に使用）',
      initial: cfg.TEST_DIR || d.testDir,
    },
    {
      type: 'confirm',
      name: 'ddd',
      message: 'DDD（Domain-Driven Design）を使いますか？',
      initial: (cfg.SPEC_RUNNER_DDD_ENABLED || 'true') === 'true',
    },
    {
      type: 'confirm',
      name: 'tdd',
      message: 'TDD（テスト駆動）を必須にしますか？ 実装前にテスト設計＋テストコードを必ず書くルールになります',
      initial: (cfg.TDD_ENABLED || 'true') === 'true',
    },
    {
      type: 'select',
      name: 'ci',
      message: 'CI/CD プラットフォームを選択してください',
      choices: ['github-actions', 'gitlab-ci', 'none'],
    },
    {
      type: 'select',
      name: 'language',
      message: 'ドキュメントの言語を選択してください',
      choices: ['ja', 'en'],
    },
  ]);

  const domainPath   = (answers.domainPath || d.domainPath).trim();
  const usecasePath  = (answers.usecasePath || d.usecasePath).trim();
  const infraPath    = (answers.infraPath || d.infraPath).trim();
  const migrationDir = (answers.migrationDir || d.migrationDir).trim();
  const sourceExt    = (answers.sourceExtensions || d.sourceExtensions).trim();
  const forbiddenPat = (answers.domainForbiddenGrepPattern || d.domainForbiddenGrepPattern).trim();
  const testDir      = (answers.testDir || d.testDir).trim() || 'tests';

  const vars = {
    FRAMEWORK:                 cfg.SPEC_RUNNER_FRAMEWORK || 'custom',
    SPEC_RUNNER_TOOLS:        cfg.SPEC_RUNNER_TOOLS || 'claude,cursor,copilot',
    RUNTIME_MEMO:              (answers.runtimeMemo || '').trim().replace(/\s+/g, ' '),
    LANGUAGE:                  answers.language || 'ja',
    DDD_ENABLED:               answers.ddd ? 'true' : 'false',
    TDD_ENABLED:               answers.tdd !== false ? 'true' : 'false',
    SOURCE_EXTENSIONS:         sourceExt,
    TEST_EXTENSIONS:           d.testExtensions,
    APP_SOURCE_DIR:            d.appSourceDir,
    TEST_DIR:                  testDir,
    MIGRATION_DIR:             migrationDir,
    BUILD_CMD:                 cfg.BUILD_CMD || d.buildCmd,
    TEST_CMD:                  cfg.TEST_CMD || d.testCmd,
    LINT_CMD:                  cfg.LINT_CMD || d.lintCmd,
    DOMAIN_PATH:               domainPath,
    USECASE_PATH:              usecasePath,
    INFRA_PATH:                infraPath,
    DDD_LAYER_PATTERN:         dddLayerPatternFromPaths(domainPath, usecasePath, infraPath),
    DOMAIN_FORBIDDEN_GREP_PATTERN: forbiddenPat,
    CI_PLATFORM:               answers.ci || 'github-actions',
    DOC_LANGUAGE:              answers.language || 'ja',
    CONFIGURED:                'true',
  };

  generateConfigSh(vars);
  log('');
  ok('設定を保存しました: .spec-runner/config.sh');
  log('');
}

// ── 更新モード ────────────────────────────────────────────────────────────────
async function runUpdate() {
  log(chalk.bold('📦 spec-runner を最新版に更新します'));
  log('');

  if (!fs.existsSync(CONFIG_SH)) {
    err('.spec-runner/config.sh が見つかりません。まず npx spec-runner を実行してください。');
  }

  const configContent = fs.readFileSync(CONFIG_SH, 'utf8');
  const cfg = parseConfigSh(configContent);
  const d = DEFAULT_STRUCTURE;

  info(`現在の構造: ${cfg.DOMAIN_PATH || d.domainPath} → ${cfg.USECASE_PATH || d.usecasePath} → ${cfg.INFRA_PATH || d.infraPath}`);
  log('');

  const updateTargets = [{ rel: '.spec-runner/scripts/spec-runner.sh', from: 'base', srcRel: 'scripts/spec-runner.sh' }];
  if (fs.existsSync(path.join(CWD, '.claude'))) {
    updateTargets.push(
      { rel: '.claude/hooks/pre-tool-use.sh', from: 'claude' },
      { rel: '.claude/settings.json', from: 'claude' },
    );
  }

  const templatesDir = path.join(PKG_DIR, 'templates');
  const vars = {
    FRAMEWORK:                 cfg.SPEC_RUNNER_FRAMEWORK || 'custom',
    LANGUAGE:                  cfg.SPEC_RUNNER_LANGUAGE || 'ja',
    DDD_ENABLED:               cfg.SPEC_RUNNER_DDD_ENABLED || 'true',
    SOURCE_EXTENSIONS:         cfg.SOURCE_EXTENSIONS || d.sourceExtensions,
    TEST_EXTENSIONS:           cfg.TEST_EXTENSIONS || d.testExtensions,
    APP_SOURCE_DIR:            cfg.APP_SOURCE_DIR || d.appSourceDir,
    TEST_DIR:                  cfg.TEST_DIR || d.testDir,
    MIGRATION_DIR:             cfg.MIGRATION_DIR || d.migrationDir,
    BUILD_CMD:                 cfg.BUILD_CMD || d.buildCmd,
    TEST_CMD:                  cfg.TEST_CMD || d.testCmd,
    LINT_CMD:                  cfg.LINT_CMD || d.lintCmd,
    DOMAIN_PATH:               cfg.DOMAIN_PATH || d.domainPath,
    USECASE_PATH:              cfg.USECASE_PATH || d.usecasePath,
    INFRA_PATH:                cfg.INFRA_PATH || d.infraPath,
    DDD_LAYER_PATTERN:         cfg.DDD_LAYER_PATTERN || dddLayerPatternFromPaths(cfg.DOMAIN_PATH, cfg.USECASE_PATH, cfg.INFRA_PATH),
    DOMAIN_FORBIDDEN_GREP_PATTERN: cfg.DOMAIN_FORBIDDEN_GREP_PATTERN || '',
    CI_PLATFORM:              cfg.CI_PLATFORM || 'github-actions',
    DOC_LANGUAGE:              cfg.SPEC_RUNNER_DOC_LANGUAGE || 'ja',
    USECASE:                   '',
    DATE:                      new Date().toISOString().slice(0, 10),
  };

  // 要件定義テンプレートが無ければ追加（init で必須のため）
  const requirementTemplateDest = path.join(CWD, '.spec-runner', 'templates', '01_要件定義', 'ひな形.md');
  if (!fs.existsSync(requirementTemplateDest)) {
    const requirementTemplateSrc = path.join(templatesDir, 'base', 'templates', '01_要件定義', 'ひな形.md');
    if (fs.existsSync(requirementTemplateSrc)) {
      copyFile(requirementTemplateSrc, requirementTemplateDest, vars);
    }
  }

  log(chalk.bold('更新するファイル:'));
  for (const { rel, from, srcRel } of updateTargets) {
    const srcDir = path.join(templatesDir, from);
    const src  = path.join(srcDir, srcRel || rel);
    const dest = path.join(CWD, rel);
    if (fs.existsSync(src)) {
      // バックアップ
      if (fs.existsSync(dest) && !isDryRun) {
        fs.copyFileSync(dest, dest + '.bak');
      }
      copyFile(src, dest, vars);
    }
  }

  // 実行権限
  const devShPath = path.join(CWD, '.spec-runner', 'scripts', 'spec-runner.sh');
  if (fs.existsSync(devShPath) && !isDryRun) fs.chmodSync(devShPath, '755');

  log('');
  log(chalk.bold.green('✅ 更新完了'));
  info('バックアップ: .spec-runner/scripts/spec-runner.sh.bak など');
}

// ── エントリー ────────────────────────────────────────────────────────────────
main().catch(e => {
  console.error(chalk.red('予期せぬエラーが発生しました:'), e.message);
  process.exit(1);
});
