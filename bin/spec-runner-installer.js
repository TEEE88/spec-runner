#!/usr/bin/env node
"use strict";

/**
 * spec-runner インストーラ（Claude / GitHub Copilot 選択式）
 *
 * docs を正本にした開発運用ハーネスをプロジェクトへ導入する。
 * 現在の配布物は原則次のとおり:
 * - Claude: `./.claude/**`
 * - Copilot: `./.github/**`
 *
 * ポリシー:
 * - 通常実行では「既存があるものは上書きしない」（差分バックアップは FORCE 時のみ）
 * - FORCE 時のみ、差分のある既存を `.spec-runner/archive/<timestamp>/...` に退避して上書き
 */

const fs = require("fs");
const path = require("path");

const CWD = process.cwd();
const PKG_DIR = path.resolve(__dirname, "..");

const DEST_CLAUDE_DIR = path.join(CWD, ".claude");
const DEST_GITHUB_DIR = path.join(CWD, ".github");

const FORCE = process.env.SPEC_RUNNER_FORCE === "1";
const TARGET = (process.env.SPEC_RUNNER_TARGET || "").trim().toLowerCase();

const TEMPLATE_ROOT = path.join(PKG_DIR, "spec-runner", "templates");
const CLAUDE_TEMPLATE_DIR = path.join(TEMPLATE_ROOT, ".claude");
const COPILOT_TEMPLATE_DIR = path.join(TEMPLATE_ROOT, ".github");

function parseArgs(argv) {
  const out = { target: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--target" && i + 1 < argv.length) {
      out.target = String(argv[i + 1] || "").trim().toLowerCase();
      i += 1;
      continue;
    }
    if (a.startsWith("--target=")) {
      out.target = a.slice("--target=".length).trim().toLowerCase();
      continue;
    }
  }
  return out;
}

function exists(p) {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function isoTimestampSafe() {
  // 例: 2026-04-02T12:34:56.789Z -> 2026-04-02T12-34-56-789Z
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function readFileText(p) {
  return fs.readFileSync(p, "utf8");
}

function writeFileText(p, content) {
  ensureDir(path.dirname(p));
  fs.writeFileSync(p, content, "utf8");
}

function filesEqual(a, b) {
  const bufA = fs.readFileSync(a);
  const bufB = fs.readFileSync(b);
  return bufA.equals(bufB);
}

function mergeJsonDeep(base, override) {
  const result = { ...base };
  for (const [key, val] of Object.entries(override)) {
    if (Array.isArray(val) && Array.isArray(result[key])) {
      // 配列は重複を避けてマージ
      const existing = result[key].map((item) => JSON.stringify(item));
      const additions = val.filter((item) => !existing.includes(JSON.stringify(item)));
      result[key] = [...result[key], ...additions];
    } else if (val && typeof val === "object" && result[key] && typeof result[key] === "object") {
      result[key] = mergeJsonDeep(result[key], val);
    } else {
      result[key] = val;
    }
  }
  return result;
}

function copySettingsJsonWithMerge(src, dest, archiveRoot) {
  if (!exists(dest)) {
    writeFileText(dest, readFileText(src));
    return;
  }
  let existing, incoming;
  try {
    existing = JSON.parse(readFileText(dest));
    incoming = JSON.parse(readFileText(src));
  } catch {
    // JSON パース失敗時は通常の copyFileWithPolicy にフォールバック
    copyFileWithPolicy(src, dest, archiveRoot);
    return;
  }
  const merged = mergeJsonDeep(existing, incoming);
  if (JSON.stringify(merged) === JSON.stringify(existing)) return; // 変更なし
  if (FORCE && archiveRoot) {
    const ap = archivePathFor(dest, archiveRoot);
    ensureDir(path.dirname(ap));
    fs.copyFileSync(dest, ap);
  }
  writeFileText(dest, JSON.stringify(merged, null, 2) + "\n");
}

function appendToGitignore(lines, dest) {
  let content = exists(dest) ? readFileText(dest) : "";
  const additions = lines.filter((line) => !content.split("\n").includes(line));
  if (additions.length === 0) return;
  const sep = content === "" || content.endsWith("\n") ? "" : "\n";
  writeFileText(dest, content + sep + additions.join("\n") + "\n");
}

function normalizeTarget(t) {
  if (!t) return "";
  const x = String(t).trim().toLowerCase();
  if (x === "claude" || x === "c") return "claude";
  if (x === "copilot" || x === "github" || x === "gh" || x === "g") return "copilot";
  if (x === "both" || x === "all") return "both";
  return "";
}

function isTTY() {
  try {
    return !!process.stdin.isTTY;
  } catch {
    return false;
  }
}

function promptLine(question) {
  process.stdout.write(question);
  // stdin (fd 0) may be in non-blocking mode (EAGAIN); read from /dev/tty directly
  try {
    const { execSync } = require("child_process");
    const result = execSync('IFS= read -r REPLY < /dev/tty && printf "%s" "$REPLY"', {
      shell: "/bin/sh",
      stdio: ["ignore", "pipe", "inherit"],
    });
    return String(result || "").trim();
  } catch {
    return String(fs.readFileSync(0, "utf8") || "").trim();
  }
}

function promptTargetInteractive() {
  if (!isTTY()) return "claude";

  const ans = promptLine(
    "インストール先を選んでください:\n" +
    "  1) Claude Code（.claude）\n" +
    "  2) GitHub Copilot（.github）\n" +
    "  3) 両方\n" +
    "選択 [1/2/3] : "
  );
  if (ans === "2") return "copilot";
  if (ans === "3") return "both";
  return "claude";
}

function archivePathFor(destPath, archiveRoot) {
  // destPath は CWD の配下を想定
  const rel = path.relative(CWD, destPath);
  return path.join(archiveRoot, rel);
}

function copyFileWithPolicy(src, dest, archiveRoot) {
  if (!exists(dest)) {
    writeFileText(dest, readFileText(src));
    return { changed: true, overwritten: false, archived: false, destWasMissing: true };
  }

  if (!FORCE) {
    return { changed: false, overwritten: false, archived: false, destWasMissing: false };
  }

  if (filesEqual(src, dest)) {
    return { changed: false, overwritten: false, archived: false, destWasMissing: false };
  }

  // FORCE: 差分がある場合は既存を退避して上書き
  if (archiveRoot) {
    const ap = archivePathFor(dest, archiveRoot);
    ensureDir(path.dirname(ap));
    fs.copyFileSync(dest, ap);
  }
  writeFileText(dest, readFileText(src));
  return { changed: true, overwritten: true, archived: !!archiveRoot, destWasMissing: false };
}

function walkFiles(dir, onFile) {
  if (!exists(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(full, onFile);
    } else if (entry.isFile()) {
      onFile(full);
    }
  }
}

function dirHasFiles(dir) {
  let found = false;
  walkFiles(dir, () => {
    found = true;
  });
  return found;
}

function mirrorTreeTo(destRootDir, templateDir, archiveRoot) {
  if (!exists(templateDir)) {
    throw new Error(`テンプレートが見つかりません: ${templateDir}`);
  }

  walkFiles(templateDir, (srcFile) => {
    const rel = path.relative(templateDir, srcFile);
    const destFile = path.join(destRootDir, rel);
    // settings.json は上書きではなくマージ
    if (path.basename(srcFile) === "settings.json") {
      copySettingsJsonWithMerge(srcFile, destFile, archiveRoot);
      return;
    }
    copyFileWithPolicy(srcFile, destFile, archiveRoot);
  });
}

function copySkillTree(skillsRoot, destRootDir, archiveRoot) {
  if (!exists(skillsRoot)) return;

  walkFiles(skillsRoot, (skillFile) => {
    const rel = path.relative(skillsRoot, skillFile);
    const destFile = path.join(destRootDir, "skills", rel);
    copyFileWithPolicy(skillFile, destFile, archiveRoot);
  });
}

function parseYamlPathsFromFrontmatter(yamlText) {
  // 仕様簡易: paths: ["a","b"] のような1行配列を優先抽出
  const m = yamlText.match(/paths:\s*\[(.*?)\]/s);
  if (!m) return null;
  const inner = m[1];
  const strMatches = Array.from(inner.matchAll(/"([^"]+)"|'([^']+)'/g)).map((mm) => mm[1]);
  if (!strMatches.length) return null;
  return strMatches.join(",");
}

function convertRuleToCopilotInstructionMarkdown(ruleMarkdown) {
  // `.claude/rules/*.md` の YAML を `.github/instructions/*.instructions.md` の applyTo に変換
  if (!ruleMarkdown.startsWith("---")) {
    return `---\napplyTo: "**"\n---\n\n${ruleMarkdown}`;
  }
  const parts = ruleMarkdown.split(/^---\s*$/m);
  if (parts.length < 3) {
    return `---\napplyTo: "**"\n---\n\n${ruleMarkdown}`;
  }
  const yamlText = parts[1] ?? "";
  const bodyText = parts.slice(2).join("---").replace(/^\n/, "");
  const applyTo = parseYamlPathsFromFrontmatter(yamlText) ?? "**";
  return `---\napplyTo: "${applyTo}"\n---\n\n${bodyText}`;
}

function installCopilotFromClaudeTemplate(archiveRoot) {
  const rulesRoot = path.join(CLAUDE_TEMPLATE_DIR, "rules");
  const agentsRoot = path.join(CLAUDE_TEMPLATE_DIR, "agents");

  // rules -> .github/instructions/*.instructions.md
  if (exists(rulesRoot)) {
    walkFiles(rulesRoot, (ruleFile) => {
      if (!ruleFile.endsWith(".md")) return;
      const rel = path.relative(rulesRoot, ruleFile);
      const relDir = path.dirname(rel);
      const base = path.basename(rel, ".md");
      const destDir = path.join(DEST_GITHUB_DIR, "instructions", relDir === "." ? "" : relDir);
      const destFile = path.join(destDir, `${base}.instructions.md`);
      if (exists(destFile) && !FORCE) return;
      if (exists(destFile) && FORCE && archiveRoot) {
        const ap = archivePathFor(destFile, archiveRoot);
        ensureDir(path.dirname(ap));
        fs.copyFileSync(destFile, ap);
      }
      const converted = convertRuleToCopilotInstructionMarkdown(readFileText(ruleFile));
      writeFileText(destFile, converted);
    });
  }

  // agents -> .github/agents/*.agent.md（中身はそのまま）
  if (exists(agentsRoot)) {
    walkFiles(agentsRoot, (agentFile) => {
      if (!agentFile.endsWith(".md")) return;
      const rel = path.relative(agentsRoot, agentFile);
      const relDir = path.dirname(rel);
      const base = path.basename(rel, ".md");
      const destDir = path.join(DEST_GITHUB_DIR, "agents", relDir === "." ? "" : relDir);
      const destFile = path.join(destDir, `${base}.agent.md`);
      copyFileWithPolicy(agentFile, destFile, archiveRoot);
    });
  }

  // skills -> .github/skills/**（templates / references を含めて同構造コピー）
  copySkillTree(path.join(CLAUDE_TEMPLATE_DIR, "skills"), DEST_GITHUB_DIR, archiveRoot);
}

function printBanner() {
  console.log("");
  console.log("╔════════════════════════════════════════╗");
  console.log("║        spec-runner インストーラ        ║");
  console.log("║   docs正本ハーネスをプロジェクトへ導入   ║");
  console.log("╚════════════════════════════════════════╝");
  console.log("");
}

function printNextSteps() {
  console.log("─────────────────────────────────────────");
  console.log("次のステップ:");
  console.log("");
  console.log("  Claude Code を開いて、作りたいものを伝えてください。");
  console.log("  セットアップが自動で始まります。");
  console.log("─────────────────────────────────────────");
}

function main() {
  printBanner();

  const args = parseArgs(process.argv.slice(2));
  let target = normalizeTarget(args.target) || normalizeTarget(TARGET);
  if (!target) target = promptTargetInteractive();

  const ts = FORCE ? isoTimestampSafe() : null;
  const archiveRoot = ts ? path.join(CWD, ".spec-runner", "archive", ts) : null;

  if (!exists(CLAUDE_TEMPLATE_DIR)) {
    throw new Error(`Claude テンプレートが見つかりません: ${CLAUDE_TEMPLATE_DIR}`);
  }

  // CLAUDE.md をプロジェクトルートへインストール（target によらず常に配置）
  const claudeMdSrc = path.join(TEMPLATE_ROOT, "CLAUDE.md");
  if (exists(claudeMdSrc)) {
    copyFileWithPolicy(claudeMdSrc, path.join(CWD, "CLAUDE.md"), archiveRoot);
  }

  // .spec-runner/scripts を導入（target によらず常に配置）
  const specRunnerTemplateDir = path.join(TEMPLATE_ROOT, ".spec-runner");
  if (exists(specRunnerTemplateDir)) {
    mirrorTreeTo(path.join(CWD, ".spec-runner"), specRunnerTemplateDir, archiveRoot);
  }

  // .gitignore に scan キャッシュを追記
  appendToGitignore([".spec-runner/scan/"], path.join(CWD, ".gitignore"));

  console.log("");
  if (target === "claude" || target === "both") {
    mirrorTreeTo(DEST_CLAUDE_DIR, CLAUDE_TEMPLATE_DIR, archiveRoot);
  }
  if (target === "copilot" || target === "both") {
    ensureDir(DEST_GITHUB_DIR);
    if (dirHasFiles(COPILOT_TEMPLATE_DIR)) {
      mirrorTreeTo(DEST_GITHUB_DIR, COPILOT_TEMPLATE_DIR, archiveRoot);
      const copilotSkillsRoot = path.join(COPILOT_TEMPLATE_DIR, "skills");
      if (!dirHasFiles(copilotSkillsRoot)) {
        copySkillTree(path.join(CLAUDE_TEMPLATE_DIR, "skills"), DEST_GITHUB_DIR, archiveRoot);
      }
    } else {
      installCopilotFromClaudeTemplate(archiveRoot);
    }
  }

  console.log("");
  if (target === "claude") console.log("完了: .claude/ を導入しました。");
  else if (target === "copilot") console.log("完了: .github/ を導入しました。");
  else console.log("完了: .claude/ と .github/ を導入しました。");
  console.log("");
  printNextSteps();
}

main();
