---
description: rules・agents・skills ファイルのフォーマット定義。harness-engineering や architecture-skill-development で新規作成・修正するときに参照する。
---

# ハーネスファイルフォーマット

## rule ファイル（`.claude/rules/*.md`）

```markdown
---
description: このルールの概要（1行）
paths: ["対象パス/**"]   # 省略すると全ファイルに適用
---

# ルール名

本文...
```

- `description` は必須。Claude がルールを選択するときに使う
- `paths` は省略可。省略すると `**` 相当（全ファイルに適用）
- `integrations` に `github` が含まれる場合、対応する `.github/instructions/{name}.instructions.md` も作成・更新する
  - `.github/` 版のヘッダーは `applyTo: "対象パス/**"` 形式に変換する

## agent ファイル（`.claude/agents/*.md`）

```markdown
---
name: agent-name
description: いつ・何のために呼ぶかを具体的に書く（トリガー型）
tools: Read, Grep, Glob          # 必要最小限のツールだけ付与
model: sonnet                    # 通常は sonnet
---

# エージェント名

本文...
```

- `description` はトリガー型で書く（「〇〇のときに自動で呼ぶ」形式）
- `tools` は最小権限原則。読み取りのみなら `Read, Grep, Glob`
- 書き込みが必要な場合のみ `Edit, Write` を追加する
- `integrations` に `github` が含まれる場合、対応する `.github/agents/{name}.agent.md` も作成・更新する

## skill ファイル（`.claude/skills/{name}/SKILL.md`）

```markdown
---
name: skill-name
description: このスキルの目的と使うタイミング（1〜2行）
---

# スキル名

本文...
```

- `description` は Claude がスキルを選択するときに使う。「いつ使うか」を含める
- `integrations` に `github` が含まれる場合、対応する `.github/skills/{name}/SKILL.md` も作成・更新する

## CLAUDE.md

CLAUDE.md は全会話で常にコンテキストに読み込まれる。書くほどコストが増えるため、最小に保つ。

### 書いてよいもの

- よく使う skill の名前と起動タイミング（開発ワークフローの入口）
- プロジェクト全体に常時適用すべき制約（例: 言語、承認フロー）

### 書いてはいけないもの（代わりの置き場所）

| 内容 | 正しい置き場所 |
|------|--------------|
| コーディング規約の詳細 | `.claude/rules/code-style.md` |
| フォーマット定義・手順 | `.claude/rules/*.md` |
| スキルの詳細フロー | `.claude/skills/*/SKILL.md` |
| 過去の決定・背景 | `docs/02_概要設計/90_ADR/` |

### 目安

- 20 行を超えたら見直しを検討する
- 新しい内容を追加する前に「rules / skills に移せないか」を先に考える

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
