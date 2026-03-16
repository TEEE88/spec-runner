#!/usr/bin/env node
"use strict";

/**
 * spec-runner インストーラー（templates/.spec-runner ベース）
 *
 * ゴール:
 * - `npx spec-runner` または `npm exec spec-runner` を実行すると、
 *   プロジェクト直下に `./.spec-runner/` フォルダを作成する。
 * - `./.spec-runner/spec-runner.sh 次のステップ --json` を叩けば
 *   「現在フェーズ」と「やるべきステップ .md」が 1 本だけ返ってくる。
 * - メッセージ・ファイルはすべて日本語のみ。
 *
 * 重要:
 * - すでに `.spec-runner/` が存在する場合はデフォルトでは上書きしない。
 *   上書きしたい場合は、環境変数 `SPEC_RUNNER_FORCE=1` を付けて実行する。
 */

const fs = require("fs");
const path = require("path");

const CWD = process.cwd();
const PKG_DIR = path.resolve(__dirname, "..");
// パッケージ内の公式テンプレート配置場所
const TEMPLATE_SPEC_RUNNER_DIR = path.join(PKG_DIR, "templates", ".spec-runner");
// 展開先（ユーザープロジェクト側）
const DEST_DIR = path.join(CWD, ".spec-runner");

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

function writeJsonPretty(destPath, obj) {
  fs.mkdirSync(path.dirname(destPath), { recursive: true });
  fs.writeFileSync(destPath, JSON.stringify(obj, null, 2) + "\n", "utf8");
  ok(path.relative(CWD, destPath));
}

function main() {
  log("");
  log("╔════════════════════════════════════════╗");
  log("║        spec-runner インストーラ        ║");
  log("║     フェーズ駆動 / 次のステップ方式     ║");
  log("╚════════════════════════════════════════╝");
  log("");

  if (!exists(TEMPLATE_SPEC_RUNNER_DIR)) {
    error("パッケージ内に templates/.spec-runner テンプレートが見つかりません。");
    process.exit(1);
  }

  if (exists(DEST_DIR) && process.env.SPEC_RUNNER_FORCE !== "1") {
    error(".spec-runner/ フォルダがすでに存在します。");
    info("上書きする場合は、環境変数 SPEC_RUNNER_FORCE=1 を付けて実行してください。");
    info("例: SPEC_RUNNER_FORCE=1 npx spec-runner");
    process.exit(1);
  }

  if (exists(DEST_DIR) && process.env.SPEC_RUNNER_FORCE === "1") {
    info("既存の .spec-runner/ を上書きします（SPEC_RUNNER_FORCE=1）。");
  }

  info(".spec-runner/ を展開しています...");
  const skipNames = new Set([
    "project.json",
    "phase-locks.json",
    "grade-history.json",
  ]);
  copyDirRecursively(TEMPLATE_SPEC_RUNNER_DIR, DEST_DIR, { skipNames });

  // 2. project.json を project.json.example から生成（存在すれば）
  const examplePath = path.join(TEMPLATE_SPEC_RUNNER_DIR, "project.json.example");
  const projectJsonDest = path.join(DEST_DIR, "project.json");
  if (exists(examplePath)) {
    const content = fs.readFileSync(examplePath, "utf8");
    fs.writeFileSync(projectJsonDest, content, "utf8");
    ok(path.relative(CWD, projectJsonDest));
  } else {
    // フォールバック（最低限の既定値）
    const fallback = {
      naming: {
        branch_prefix: "feature",
        uc_id_pattern: "UC-[0-9]{3}",
        uc_spec_basename: "{uc_id}-{slug}.md",
        adr_basename: "MMDD-{title}.md",
        docs_05_categories: true,
        other_work_prefixes: ["work", "infra", "cicd"],
      },
      required_docs: {
        charter: ["docs/01_憲章/憲章.md"],
      },
      test_design: {
        dir: "tests",
        pattern: "*.spec.*",
      },
      test_command: {
        run: "npm test",
      },
    };
    writeJsonPretty(projectJsonDest, fallback);
  }

  // 3. phase-locks.json / grade-history.json を初期状態で作成
  const phaseLocksDest = path.join(DEST_DIR, "phase-locks.json");
  const gradeHistoryDest = path.join(DEST_DIR, "grade-history.json");

  const phaseLocks = {
    _comment:
      "フェーズ完了状態の単一ソース。初期状態ではすべて未完了。レビュー状態もここで管理する。",
    charter: {
      completed: false,
      phase: 0,
      phase_name: "憲章策定",
      locked_at: null,
      reviewed_by: null,
      document: "docs/01_憲章/憲章.md",
      version: "v0.0.0",
    },
    domain: {
      completed: false,
      phase: 1,
      phase_name: "ドメイン設計",
      locked_at: null,
      reviewed_by: null,
      documents: [
        "docs/02_ドメイン設計/ユビキタス言語辞書.md",
        "docs/02_ドメイン設計/ドメインモデル.md",
        "docs/02_ドメイン設計/集約.md",
      ],
    },
    architecture: {
      completed: false,
      phase: 2,
      phase_name: "アーキテクチャ選択",
      locked_at: null,
      reviewed_by: null,
      documents: [
        "docs/03_アーキテクチャ/パターン選定.md",
        "docs/03_アーキテクチャ/インフラ方針.md",
        "docs/03_アーキテクチャ/設計判断記録",
      ],
    },
    infra: {
      completed: false,
      phase: 4,
      phase_name: "インフラ詳細設計",
      locked_at: null,
    },
    test_design: {
      completed: false,
    },
    uc_reviewed: [],
  };

  const gradeHistory = {
    current_grade: "LOOP1",
    history: [],
  };

  writeJsonPretty(phaseLocksDest, phaseLocks);
  writeJsonPretty(gradeHistoryDest, gradeHistory);

  const commandTmpl = path.join(PKG_DIR, "templates", "spec-runner-command.md");
  if (exists(commandTmpl)) {
    const cmdContent = fs.readFileSync(commandTmpl, "utf8");
    const claudeCmd = path.join(CWD, ".claude", "commands", "spec-runner.md");
    const cursorCmd = path.join(CWD, ".cursor", "commands", "spec-runner.md");
    fs.mkdirSync(path.dirname(claudeCmd), { recursive: true });
    fs.mkdirSync(path.dirname(cursorCmd), { recursive: true });
    fs.writeFileSync(claudeCmd, cmdContent, "utf8");
    fs.writeFileSync(cursorCmd, cmdContent, "utf8");
    ok(path.relative(CWD, claudeCmd));
    ok(path.relative(CWD, cursorCmd));
  }

  log("");
  log("次のステップ:");
  log("  1. プロジェクトルートで:");
  log("");
  log("       ./.spec-runner/spec-runner.sh 次のステップ --json");
  log("");
  log("  2. 出力の command_file（.spec-runner/steps/*.md）を開き、その指示に従う。");
  log("  3. 終わったら再度上記を実行して次に進む。");
  log("");
  log("  AI では「/spec-runner を実行して」と伝えればよい。");
  log("");
}

main();
