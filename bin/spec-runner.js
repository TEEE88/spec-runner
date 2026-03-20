#!/usr/bin/env node
"use strict";

/**
 * spec-runner インストーラー（templates/.spec-runner ベース）
 *
 * ゴール:
 * - `npx spec-runner` または `npm exec spec-runner` を実行すると、
 *   プロジェクト直下に `./.spec-runner/` フォルダを作成する。
 * - Claude Code から `/spec-runner` を実行すれば、
 *   「現在フェーズ」と「やるべきステップ .md」が 1 本だけ返ってくる。
 * - メッセージ・ファイルはすべて日本語のみ。
 *
 * 重要:
 * - すでに `.spec-runner/` が存在する場合はデフォルトでは上書きしない。
 *   上書きしたい場合は、環境変数 `SPEC_RUNNER_FORCE=1` を付けて実行する。
 *
 * 必須テンプレ（パッケージ内）:
 * - templates/.spec-runner/project.json.example
 * - templates/.spec-runner/templates/phase-locks.json
 * - templates/.spec-runner/templates/grade-history.json
 *
 * MkDocs（任意・プロジェクトルート）:
 * - templates/mkdocs-scaffold/ の mkdocs.yml / requirements-docs.txt / docs/index.md を
 *   未有効時のみコピー（憲章・設計書は既存の docs/01..06 をそのまま閲覧）
 * - パッケージ同梱の docs/flow.md を docs/spec-runner-フロー.md としてコピー（未存在時のみ）
 */

const fs = require("fs");
const path = require("path");

const CWD = process.cwd();
const PKG_DIR = path.resolve(__dirname, "..");
const TEMPLATE_SPEC_RUNNER_DIR = path.join(PKG_DIR, "templates", ".spec-runner");
const DEST_DIR = path.join(CWD, ".spec-runner");
const TEMPLATES_DIR = path.join(TEMPLATE_SPEC_RUNNER_DIR, "templates");
const PHASE_LOCKS_TEMPLATE = path.join(TEMPLATES_DIR, "phase-locks.json");
const GRADE_HISTORY_TEMPLATE = path.join(TEMPLATES_DIR, "grade-history.json");
const MKDOCS_SCAFFOLD_DIR = path.join(PKG_DIR, "templates", "mkdocs-scaffold");
const FLOW_DOC_SRC = path.join(PKG_DIR, "docs", "flow.md");

/** コピー時はスキップし、FORCE 時は消さない（ユーザー状態を保持） */
const USER_STATE_BASENAMES = new Set([
  "project.json",
  "phase-locks.json",
  "grade-history.json",
]);

function log(msg) {
  console.log(msg);
}

function info(msg) {
  console.log(`ℹ ${msg}`);
}

function ok(msg) {
  console.log(`✓ ${msg}`);
}

function error(msg) {
  console.error(`ERROR: ${msg}`);
}

function exists(p) {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

function ensureTemplateDirOrExit() {
  if (!exists(TEMPLATE_SPEC_RUNNER_DIR)) {
    error("パッケージ内に templates/.spec-runner テンプレートが見つかりません。");
    process.exit(1);
  }
  if (!exists(path.join(TEMPLATE_SPEC_RUNNER_DIR, "project.json.example"))) {
    error("必須テンプレ project.json.example が見つかりません。");
    process.exit(1);
  }
  if (!exists(PHASE_LOCKS_TEMPLATE)) {
    error("必須テンプレ templates/phase-locks.json が見つかりません。");
    process.exit(1);
  }
  if (!exists(GRADE_HISTORY_TEMPLATE)) {
    error("必須テンプレ templates/grade-history.json が見つかりません。");
    process.exit(1);
  }
}

function assertDestInstallableOrExit() {
  const force = process.env.SPEC_RUNNER_FORCE === "1";
  if (!exists(DEST_DIR)) return;
  if (force) {
    info("既存の .spec-runner/ を上書きします（SPEC_RUNNER_FORCE=1）。");
    return;
  }
  error(".spec-runner/ フォルダがすでに存在します。");
  info("上書きする場合は、環境変数 SPEC_RUNNER_FORCE=1 を付けて実行してください。");
  info("例: SPEC_RUNNER_FORCE=1 npx spec-runner");
  process.exit(1);
}

/** FORCE 時: テンプレから消えたファイルも反映できるよう、保持対象以外を削除 */
function wipeDestExceptUserState() {
  if (!exists(DEST_DIR) || process.env.SPEC_RUNNER_FORCE !== "1") return;
  for (const entry of fs.readdirSync(DEST_DIR, { withFileTypes: true })) {
    if (USER_STATE_BASENAMES.has(entry.name)) continue;
    fs.rmSync(path.join(DEST_DIR, entry.name), { recursive: true, force: true });
  }
}

function copyDirRecursively(src, dest, options = {}) {
  const { skipNames = new Set() } = options;
  if (!exists(src)) return;
  const stat = fs.statSync(src);
  if (!stat.isDirectory()) {
    throw new Error(`ディレクトリではありません: ${src}`);
  }

  fs.mkdirSync(dest, { recursive: true });

  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (skipNames.has(entry.name)) continue;
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDirRecursively(srcPath, destPath, { skipNames });
    } else {
      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      fs.copyFileSync(srcPath, destPath);
      ok(path.relative(CWD, destPath));
    }
  }
}

function expandTemplateTree() {
  copyDirRecursively(TEMPLATE_SPEC_RUNNER_DIR, DEST_DIR, {
    skipNames: USER_STATE_BASENAMES,
  });
}

function bootstrapProjectJson() {
  const examplePath = path.join(TEMPLATE_SPEC_RUNNER_DIR, "project.json.example");
  const projectJsonDest = path.join(DEST_DIR, "project.json");
  fs.writeFileSync(projectJsonDest, fs.readFileSync(examplePath, "utf8"), "utf8");
  ok(path.relative(CWD, projectJsonDest));
}

/**
 * フェーズ用 JSON は templates/.spec-runner/templates/*.json を正とする。
 * .spec-runner/ 直下に無いときだけコピー（既存のロックは上書きしない）。
 */
function writeInitialLocksAndGrade() {
  const locksDest = path.join(DEST_DIR, "phase-locks.json");
  if (!exists(locksDest)) {
    fs.copyFileSync(PHASE_LOCKS_TEMPLATE, locksDest);
    ok(path.relative(CWD, locksDest));
  }

  const gradeDest = path.join(DEST_DIR, "grade-history.json");
  if (!exists(gradeDest)) {
    fs.copyFileSync(GRADE_HISTORY_TEMPLATE, gradeDest);
    ok(path.relative(CWD, gradeDest));
  }
}

function installClaudeCommandIfPresent() {
  const commandTmpl = path.join(PKG_DIR, "templates", "spec-runner-command.md");
  if (!exists(commandTmpl)) return;
  const claudeCmd = path.join(CWD, ".claude", "commands", "spec-runner.md");
  fs.mkdirSync(path.dirname(claudeCmd), { recursive: true });
  fs.writeFileSync(claudeCmd, fs.readFileSync(commandTmpl, "utf8"), "utf8");
  ok(path.relative(CWD, claudeCmd));
}

/**
 * MkDocs + Material 用のファイルをプロジェクトルートに配置（未存在時のみ）。
 * 設計書本体は steps.json どおり docs/01..06 に置かれ、mkdocs の docs_dir でそのまま掲載する。
 */
function copyFileIfMissing(src, dest) {
  if (!exists(src) || exists(dest)) return false;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  ok(path.relative(CWD, dest));
  return true;
}

function appendGitignoreVenvDocsIfNeeded() {
  const gitignorePath = path.join(CWD, ".gitignore");
  const marker = ".venv-docs/";
  if (!exists(gitignorePath)) return;
  const raw = fs.readFileSync(gitignorePath, "utf8");
  const lines = raw.split(/\r?\n/);
  if (lines.some((line) => /^\.venv-docs\/?$/.test(line.trim()))) return;
  fs.appendFileSync(
    gitignorePath,
    `\n# spec-runner: MkDocs 用 Python 仮想環境\n${marker}\n`,
    "utf8",
  );
  ok(`${path.relative(CWD, gitignorePath)}（${marker} を追記）`);
}

function installMkdocsScaffold() {
  if (!exists(MKDOCS_SCAFFOLD_DIR)) {
    info("MkDocs テンプレート（templates/mkdocs-scaffold）が見つかりません。スキップします。");
    return;
  }
  info("MkDocs 用ファイル（不足分のみ）をプロジェクトルートに配置します...");
  copyFileIfMissing(
    path.join(MKDOCS_SCAFFOLD_DIR, "mkdocs.yml"),
    path.join(CWD, "mkdocs.yml"),
  );
  copyFileIfMissing(
    path.join(MKDOCS_SCAFFOLD_DIR, "requirements-docs.txt"),
    path.join(CWD, "requirements-docs.txt"),
  );
  copyFileIfMissing(
    path.join(MKDOCS_SCAFFOLD_DIR, "docs", "index.md"),
    path.join(CWD, "docs", "index.md"),
  );
  if (exists(FLOW_DOC_SRC)) {
    copyFileIfMissing(FLOW_DOC_SRC, path.join(CWD, "docs", "spec-runner-フロー.md"));
  }
  appendGitignoreVenvDocsIfNeeded();
}

function printBanner() {
  log("");
  log("╔════════════════════════════════════════╗");
  log("║        spec-runner インストーラ        ║");
  log("║     フェーズ駆動 / 次のステップ方式     ║");
  log("╚════════════════════════════════════════╝");
  log("");
}

function printFooter() {
  log("");
  log("設計書プレビュー（MkDocs + Material・プロジェクトルートの docs/）:");
  log("  ./.spec-runner/scripts/docs-serve.sh");
  log("");
  log("次のステップ（Claude Code 専用）:");
  log("  /spec-runner を実行して");
  log("");
}

function main() {
  printBanner();
  ensureTemplateDirOrExit();
  installMkdocsScaffold();
  assertDestInstallableOrExit();

  info(".spec-runner/ を展開しています...");
  wipeDestExceptUserState();
  expandTemplateTree();
  bootstrapProjectJson();
  writeInitialLocksAndGrade();
  installClaudeCommandIfPresent();
  printFooter();
}

main();
