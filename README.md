# spec-runner

AI は設計を飛ばして実装に走る。`docs/` があっても読まないし、仕様が曖昧なまま動くコードを返す。

`spec-runner` はそれを防ぐ。**`docs/` を正本にした開発フロー**を AI に守らせるための rules / agents / skills を、**Claude Code（`.claude/`）** と **GitHub Copilot（`.github/`）** にインストーラ一発で配る。

フローは `要件定義 → 概要設計 → 詳細設計 → TDD → 実装`。AI はこの順序で docs を読み書きしながら進み、設計なしに実装フェーズへ進めない。

インストール後は `architecture-skill-development` を使ってプロジェクトのアーキテクチャを定義し、そこから **プロジェクト専用 skill** を生やす。汎用 skill はその土台にすぎない。

## インストール

```bash
npx spec-runner
```

または:

```bash
curl -sSL https://raw.githubusercontent.com/TEEE88/spec-runner/main/install.sh | bash
```

実行時に **Claude / Copilot / 両方** を選ぶ。既存ファイルは原則上書きしない。

## 導入されるもの

### Claude を選んだ場合

```text
<project-root>/
└── .claude/
    ├── agents/
    ├── rules/
    └── skills/
```

### Copilot を選んだ場合

```text
<project-root>/
└── .github/
    ├── instructions/
    ├── agents/
    └── skills/
```

### 同梱するベース skill

**セットアップ用**（プロジェクト初期に使い、完了後はアーカイブする）

- `architecture-definition`: 新規プロジェクトで docs と architecture contract を起こす
- `existing-project-to-docs`: 既存コードから docs の draft と構造化情報を起こす
- `architecture-skill-development`: architecture contract から project 専用 skill を育てる
- `docs-driven-seed`: DDD 向けの project 専用 skill の種（`style: ddd` のとき）
- `simple-seed`: レイヤードアーキテクチャ向けの project 専用 skill の種（`style: layered` のとき）

**開発ループ用**（日常的に使う）

- `design-change`: 変更要求に対して影響調査 → ADR → 設計修正 → TDD で進める
- `test-driven-development`: アプリケーションコード向けの TDD を徹底する
- `harness-engineering`: rules / agents / skills / templates 自体を改善する
- `commit`: コミットメッセージの生成とコミット実行

`docs/` の中身は、導入後にこれらの skill を使ってプロジェクトごとに作る。

## 推奨フロー

### 新規プロジェクト

1. `architecture-definition`
2. `architecture-skill-development`
3. 生成された project 専用 skill
4. `test-driven-development`

### 既存プロジェクト

1. `existing-project-to-docs`
2. `architecture-skill-development`
3. `design-change`
4. `test-driven-development`

## 上書きインストール

差分がある既存ファイルも置換したい場合:

```bash
SPEC_RUNNER_FORCE=1 npx spec-runner
```

この場合、差分がある既存ファイルは `.spec-runner/archive/<timestamp>/...` に退避してから置換される。

## 必要環境

- Node.js 16+

## テンプレートの場所

- `spec-runner/templates/.claude/`
- `spec-runner/templates/.github/`

## バージョン運用ルール

- **開発のたびに `package.json` の `version` を更新してからコミットする**
- バージョンは原則 SemVer に従い、迷う場合はパッチを 1 つ上げる

## ライセンス

MIT
