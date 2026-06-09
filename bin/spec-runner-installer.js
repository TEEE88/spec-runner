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
 * - FORCE 時のみ、差分のある既存を `<target>/.spec-runner/archive/<timestamp>/...` に退避して上書き
 */

const fs = require("fs");
const path = require("path");

const CWD = process.cwd();
const PKG_DIR = path.resolve(__dirname, "..");

const DEST_CLAUDE_DIR = path.join(CWD, ".claude");
const DEST_GITHUB_DIR = path.join(CWD, ".github");

// target 決定後に main() 内で設定する
let specRunnerDestDir;
let specRunnerPathPrefix;

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

function applyTransformToJsonValues(obj, transform) {
  if (typeof obj === "string") return transform(obj);
  if (Array.isArray(obj)) return obj.map((item) => applyTransformToJsonValues(item, transform));
  if (obj && typeof obj === "object") {
    const result = {};
    for (const [k, v] of Object.entries(obj)) result[k] = applyTransformToJsonValues(v, transform);
    return result;
  }
  return obj;
}

function copySettingsJsonWithMerge(src, dest, archiveRoot, contentTransform) {
  if (!exists(dest)) {
    let content = readFileText(src);
    if (contentTransform) {
      try {
        const transformed = applyTransformToJsonValues(JSON.parse(content), contentTransform);
        content = JSON.stringify(transformed, null, 2) + "\n";
      } catch { /* パース失敗はそのまま書き出し */ }
    }
    writeFileText(dest, content);
    return;
  }
  let existing, incoming;
  try {
    existing = JSON.parse(readFileText(dest));
    incoming = JSON.parse(readFileText(src));
    if (contentTransform) incoming = applyTransformToJsonValues(incoming, contentTransform);
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
  console.log(`  マージ: ${path.relative(CWD, dest)}`);
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

/**
 * テキストファイルを変換して配置する（パス書き換え用）
 */
function copyTextFileWithTransform(src, dest, archiveRoot, transform) {
  const transformed = transform(readFileText(src));
  if (!exists(dest)) {
    writeFileText(dest, transformed);
    return;
  }
  if (!FORCE) return;
  const destContent = readFileText(dest);
  if (destContent === transformed) return;
  if (archiveRoot) {
    const ap = archivePathFor(dest, archiveRoot);
    ensureDir(path.dirname(ap));
    fs.copyFileSync(dest, ap);
  }
  writeFileText(dest, transformed);
}

/**
 * @param {string} destRootDir
 * @param {string} templateDir
 * @param {string|null} archiveRoot
 * @param {((s: string) => string)|null} [contentTransform] .md ファイルに適用するテキスト変換
 * @param {string[]} [excludeTopDirs] templateDir 直下のこのフォルダ名はスキップ
 */
function mirrorTreeTo(destRootDir, templateDir, archiveRoot, contentTransform, excludeTopDirs = []) {
  if (!exists(templateDir)) {
    throw new Error(`テンプレートが見つかりません: ${templateDir}`);
  }

  walkFiles(templateDir, (srcFile) => {
    const rel = path.relative(templateDir, srcFile);
    // 除外フォルダチェック（rel の最初のセグメント）
    if (excludeTopDirs.length > 0) {
      const topSeg = rel.split(path.sep)[0];
      if (excludeTopDirs.includes(topSeg)) return;
    }
    const destFile = path.join(destRootDir, rel);
    // settings.json は上書きではなくマージ
    if (path.basename(srcFile) === "settings.json") {
      copySettingsJsonWithMerge(srcFile, destFile, archiveRoot, contentTransform);
      return;
    }
    if (contentTransform && srcFile.endsWith(".md")) {
      copyTextFileWithTransform(srcFile, destFile, archiveRoot, contentTransform);
      return;
    }
    copyFileWithPolicy(srcFile, destFile, archiveRoot);
  });
}

function copySkillTree(skillsRoot, destRootDir, archiveRoot, contentTransform, skipSkills = new Set()) {
  if (!exists(skillsRoot)) return;

  walkFiles(skillsRoot, (skillFile) => {
    const rel = path.relative(skillsRoot, skillFile);
    // rel の最初のセグメントがスキル名（例: "ddd-seed/SKILL.md" → "ddd-seed"）
    const skillName = rel.split(path.sep)[0];
    if (skipSkills.has(skillName)) return;

    const destFile = path.join(destRootDir, "skills", rel);
    if (contentTransform && skillFile.endsWith(".md")) {
      copyTextFileWithTransform(skillFile, destFile, archiveRoot, contentTransform);
      return;
    }
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

function installCopilotFromClaudeTemplate(archiveRoot, contentTransform, skipSkills = new Set()) {
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
      const finalContent = contentTransform ? contentTransform(converted) : converted;
      writeFileText(destFile, finalContent);
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
      if (contentTransform) {
        copyTextFileWithTransform(agentFile, destFile, archiveRoot, contentTransform);
      } else {
        copyFileWithPolicy(agentFile, destFile, archiveRoot);
      }
    });
  }

  // skills -> .github/skills/**（templates / references を含めて同構造コピー）
  copySkillTree(path.join(CLAUDE_TEMPLATE_DIR, "skills"), DEST_GITHUB_DIR, archiveRoot, contentTransform, skipSkills);
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

  // チーム構成の選択は不要。fullstack-seed を常にインストールする
  const skipSkills = new Set();

  // target に応じて .spec-runner の配置先とパスプレフィックスを決定
  //   claude のみ → .claude/.spec-runner/
  //   copilot のみ → .github/.spec-runner/
  //   両方       → .spec-runner/（ルート：.claude / .github と同階層）
  if (target === "claude") {
    specRunnerDestDir = path.join(DEST_CLAUDE_DIR, ".spec-runner");
    specRunnerPathPrefix = ".claude/.spec-runner/";
  } else if (target === "copilot") {
    specRunnerDestDir = path.join(DEST_GITHUB_DIR, ".spec-runner");
    specRunnerPathPrefix = ".github/.spec-runner/";
  } else {
    specRunnerDestDir = path.join(CWD, ".spec-runner");
    specRunnerPathPrefix = ".spec-runner/";
  }

  // テンプレート内の '.spec-runner/' を実際のパスに書き換える変換関数
  const specRunnerTransform = (content) => content.replaceAll(".spec-runner/", specRunnerPathPrefix);

  const ts = FORCE ? isoTimestampSafe() : null;
  const specRunnerArchiveRoot = ts ? path.join(specRunnerDestDir, "archive", ts) : null;
  const claudeArchiveRoot = ts ? path.join(DEST_CLAUDE_DIR, ".archive", ts) : null;
  const copilotArchiveRoot = ts ? path.join(DEST_GITHUB_DIR, ".archive", ts) : null;

  if (!exists(CLAUDE_TEMPLATE_DIR)) {
    throw new Error(`Claude テンプレートが見つかりません: ${CLAUDE_TEMPLATE_DIR}`);
  }

  // .spec-runner を配置
  const specRunnerTemplateDir = path.join(TEMPLATE_ROOT, ".spec-runner");
  if (exists(specRunnerTemplateDir)) {
    mirrorTreeTo(specRunnerDestDir, specRunnerTemplateDir, specRunnerArchiveRoot);
  }

  // .gitignore に scan キャッシュを追記（配置先に合わせたパス）
  appendToGitignore([`${specRunnerPathPrefix}scan/`], path.join(CWD, ".gitignore"));

  console.log("");
  if (target === "claude" || target === "both") {
    const claudeMdSrc = path.join(TEMPLATE_ROOT, "CLAUDE.md");
    if (exists(claudeMdSrc)) {
      copyTextFileWithTransform(claudeMdSrc, path.join(CWD, "CLAUDE.md"), claudeArchiveRoot, specRunnerTransform);
    }
    // skills フォルダはスキップ付きで別途コピー
    mirrorTreeTo(DEST_CLAUDE_DIR, CLAUDE_TEMPLATE_DIR, claudeArchiveRoot, specRunnerTransform, ["skills"]);
    copySkillTree(path.join(CLAUDE_TEMPLATE_DIR, "skills"), DEST_CLAUDE_DIR, claudeArchiveRoot, specRunnerTransform, skipSkills);
  }
  if (target === "copilot" || target === "both") {
    ensureDir(DEST_GITHUB_DIR);
    const copilotInstructionsSrc = path.join(TEMPLATE_ROOT, "copilot-instructions.md");
    if (exists(copilotInstructionsSrc)) {
      copyTextFileWithTransform(copilotInstructionsSrc, path.join(CWD, ".github", "copilot-instructions.md"), copilotArchiveRoot, specRunnerTransform);
    }
    if (dirHasFiles(COPILOT_TEMPLATE_DIR)) {
      mirrorTreeTo(DEST_GITHUB_DIR, COPILOT_TEMPLATE_DIR, copilotArchiveRoot, specRunnerTransform, ["skills"]);
      const copilotSkillsRoot = path.join(COPILOT_TEMPLATE_DIR, "skills");
      if (!dirHasFiles(copilotSkillsRoot)) {
        copySkillTree(path.join(CLAUDE_TEMPLATE_DIR, "skills"), DEST_GITHUB_DIR, copilotArchiveRoot, specRunnerTransform, skipSkills);
      } else {
        copySkillTree(copilotSkillsRoot, DEST_GITHUB_DIR, copilotArchiveRoot, specRunnerTransform, skipSkills);
      }
    } else {
      installCopilotFromClaudeTemplate(copilotArchiveRoot, specRunnerTransform, skipSkills);
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
