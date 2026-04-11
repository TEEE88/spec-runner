---
applyTo: "**"
---

# ハーネスファイルフォーマット

## rule ファイル（`.github/instructions/*.instructions.md`）

```markdown
---
applyTo: "対象パス/**"   # 省略すると "**"（全ファイルに適用）
---

# ルール名

本文...
```

- `integrations` に `claude` が含まれる場合、対応する `.claude/rules/{name}.md` も作成・更新する

## agent ファイル（`.github/agents/*.agent.md`）

```markdown
---
name: agent-name
description: いつ・何のために呼ぶかを具体的に書く（トリガー型）
tools: Read, Grep, Glob          # 必要最小限のツールだけ付与
model: sonnet
---

# エージェント名

本文...
```

- `description` はトリガー型で書く（「〇〇のときに自動で呼ぶ」形式）
- `tools` は最小権限原則。読み取りのみなら `Read, Grep, Glob`
- `integrations` に `claude` が含まれる場合、対応する `.claude/agents/{name}.md` も作成・更新する

## skill ファイル（`.github/skills/{name}/SKILL.md`）

```markdown
---
name: skill-name
description: このスキルの目的と使うタイミング（1〜2行）
---

# スキル名

本文...
```

- `integrations` に `claude` が含まれる場合、対応する `.claude/skills/{name}/SKILL.md` も作成・更新する

## CLAUDE.md

CLAUDE.md は全会話で常にコンテキストに読み込まれる。書くほどコストが増えるため、最小に保つ。

### 書いてよいもの

- よく使う skill の名前と起動タイミング（開発ワークフローの入口）
- プロジェクト全体に常時適用すべき制約（例: 言語、承認フロー）

### 書いてはいけないもの（代わりの置き場所）

| 内容 | 正しい置き場所 |
|------|--------------|
| コーディング規約の詳細 | `.github/instructions/code-style.instructions.md` |
| フォーマット定義・手順 | `.github/instructions/*.instructions.md` |
| スキルの詳細フロー | `.github/skills/*/SKILL.md` |
| 過去の決定・背景 | `docs/02_概要設計/90_ADR/` |

### 目安

- 20 行を超えたら見直しを検討する
- 新しい内容を追加する前に「instructions / skills に移せないか」を先に考える

## 共通原則

- 更新する連携先は `architecture.yaml` の `integrations` に従う
  - `claude` のみ → `.claude/` だけ更新する。`.github/` を作成しない
  - `github` のみ → `.github/` だけ更新する。`.claude/` を作成しない
  - 両方 → `.claude/` と `.github/` を対で更新する
- `description` は「何をするか」より「いつ・なぜ使うか」を優先して書く
- 新規作成時は既存ファイルを参考にフォーマットを確認してから作る

## 書き方の原則

- H1 は用途を示す。description の言い換えは書かない
- H1 直下に説明文を置かない。description に書いたことを本文で繰り返さない
- `（読み取り専用）` のような付記は H1 に入れない。tools の構成で表現する
- agent のテンプレート注記（「このファイルはテンプレートです」）は agent ファイルに書かない。test-config.md に書く
- agent の書き順: ヘッダー → H1 → 前提・入力（必要な場合のみ） → 手順 → 報告フォーマット
