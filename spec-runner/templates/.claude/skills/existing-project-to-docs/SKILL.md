---
name: existing-project-to-docs
description: 既存プロジェクトを読み解き、docs の正本と architecture contract を起こすリバース設計フロー。
---

# existing-project-to-docs

## 全体フロー

```
Phase 1: 現状把握
Phase 1.5: docs 構成の合意
Phase 2: 要件とユースケースの抽出
Phase 3: 概要設計
Phase 4: 詳細設計
Phase 5: architecture contract 化
```

## 前提ルール

- docs は正本とし、各ドキュメントに `spec_runner`ヘッダーを付ける
- `maps_to` は必ず設定する。パス推定に頼らない
- 既存コードを正として観測する。推測する場合は明示する
- `depends_on` を使って後続変更に耐える形へ整える
- ユーザー承認なしに次フェーズへ進めない
- バックエンドの設計はすべて `docs/バックエンド/` 配下に置く
- `has_frontend: true` の場合、フロントエンドの設計は `docs/フロントエンド/` 配下に置く
- `style: ddd` の場合: UC がドメインを使う。ドメインの中に UC を入れない
- `style: ddd` の場合: 詳細設計は `01_ドメイン/` `02_ユースケース/` `03_DB・外部サービス/` の 3 層で構成する
- `style: layered` の場合: ドメイン層は持たない。ビジネスロジックは UC / サービス層で表現する
- `style: layered` の場合: 詳細設計は `01_ユースケース/` `02_DB・外部サービス/` の 2 層で構成する

## Phase 1: 現状把握

1. `src/`、`tests/`、設定ファイル、README、IaC を読む
2. 現状システムの入口、主要フロー、外部依存を一覧化する
3. フロントエンドの有無（Web UI・画面があるか）を判定する
4. `.spec-runner/intake/current-system-inventory.md` を作る
5. ユーザーに確認・承認を得る

## Phase 1.5: docs 構成の合意

ファイルを作成する前に、docs の構成をユーザーと合意する。

1. `current-system-inventory.md` を元に以下を提案する
   - `style`（`ddd` / `layered`）
   - `has_frontend`（`true` / `false`）
   - `docs/` のフォルダ構成（`バックエンド/` + 必要なら `フロントエンド/`）
   - 作成予定ファイルの一覧
2. ユーザーに確認・承認を得る
3. 承認後、`.spec-runner/architecture/architecture.yaml` を新規作成し `style` と `has_frontend` だけ先に書き込む（残りは Phase 5 で完成させる）

## Phase 2: 要件とユースケースの抽出

要件定義テンプレートは `simple-seed` に存在しないため、`style` に関わらず `ddd-seed` のテンプレートを使う。

1. `current-system-inventory.md` を起点に、既存機能からユースケースを逆算する
2. `.claude/skills/ddd-seed/templates/01_要件定義/要件定義.md` を使い `docs/バックエンド/01_要件定義/要件定義.md` を作る
3. `.claude/skills/ddd-seed/templates/02_概要設計/ユースケース一覧.md` を使い `docs/バックエンド/02_概要設計/ユースケース一覧.md` を作る
4. ドメイン用語が識別できたら `.claude/skills/ddd-seed/templates/01_要件定義/ユビキタス言語辞書.md` を使い `docs/バックエンド/01_要件定義/ユビキタス言語辞書.md` を作る
5. `has_frontend: true` の場合: `.claude/skills/frontend-seed/templates/01_要件定義/要件定義.md` を使い `docs/フロントエンド/01_要件定義/要件定義.md` も作る
6. ユーザーに確認・承認を得る

## Phase 3: 概要設計

### バックエンド

`style: ddd` の場合:

1. `.claude/skills/ddd-seed/templates/02_概要設計/システム全体俯瞰.md` を使い `docs/バックエンド/02_概要設計/システム全体俯瞰.md` を作る
2. `.claude/skills/ddd-seed/templates/02_概要設計/ドメインモデル.md` を使い `docs/バックエンド/02_概要設計/ドメインモデル.md` を作る
3. 必要なら ADR を作る（作成ルールは下記）

`style: layered` の場合:

1. `.claude/skills/simple-seed/templates/02_概要設計/システム全体俯瞰.md` を使い `docs/バックエンド/02_概要設計/システム全体俯瞰.md` を作る
2. 必要なら ADR を作る（作成ルールは下記）

### フロントエンド（has_frontend: true のみ）

1. `.claude/skills/frontend-seed/templates/02_概要設計/画面一覧.md` を使い `docs/フロントエンド/02_概要設計/画面一覧.md` を作る
2. `.claude/skills/frontend-seed/templates/02_概要設計/画面遷移図.md` を使い `docs/フロントエンド/02_概要設計/画面遷移図.md` を作る
3. `.claude/skills/frontend-seed/templates/02_概要設計/コンポーネント一覧.md` を使い `docs/フロントエンド/02_概要設計/コンポーネント一覧.md` を作る

### ADR 作成ルール（必要時のみ）

1. 提案時に必ず 3 案を比較する。ドキュメントには採用案と採用理由のみ記録する
2. ファイル名は `mmdd-{日本語タイトル}.md`

`style: ddd` の場合:

| 対象 | 配置先 |
|------|--------|
| システム横断の決定 | `docs/バックエンド/02_概要設計/90_ADR/全体/` |
| ドメイン設計の決定 | `docs/バックエンド/02_概要設計/90_ADR/ドメイン/` |
| UC フローの決定 | `docs/バックエンド/02_概要設計/90_ADR/UC/` |
| DB・外部サービスの決定 | `docs/バックエンド/02_概要設計/90_ADR/DB/` |
| フロントエンドの決定 | `docs/フロントエンド/02_概要設計/90_ADR/` |

`style: layered` の場合:

| 対象 | 配置先 |
|------|--------|
| システム横断の決定 | `docs/バックエンド/02_概要設計/90_ADR/全体/` |
| UC フローの決定 | `docs/バックエンド/02_概要設計/90_ADR/UC/` |
| DB・外部サービスの決定 | `docs/バックエンド/02_概要設計/90_ADR/DB/` |
| フロントエンドの決定 | `docs/フロントエンド/02_概要設計/90_ADR/` |

3. 採用案を概要設計へ反映してから次へ進む

ユーザーに確認・承認を得る。

## Phase 4: 詳細設計

### バックエンド

`style: ddd` の場合（ドメイン → UC → DB・外部サービス の順に設計する）:

1. `.claude/skills/ddd-seed/templates/03_詳細設計/01_ドメイン/{ドメイン名}.md` を使い、ドメインごとにビジネスルール・集約を整理し `docs/バックエンド/03_詳細設計/01_ドメイン/{ドメイン名}.md` を作る
2. `.claude/skills/ddd-seed/templates/03_詳細設計/02_ユースケース/UC-{日本語名}.md` を使い、UC ごとに `docs/バックエンド/03_詳細設計/02_ユースケース/UC-{日本語名}.md` を作る（シーケンス図は Mermaid で埋め込む）
3. DB・外部サービスの仕様が必要なら `docs/バックエンド/03_詳細設計/03_DB・外部サービス/` を作る

`style: layered` の場合（UC → DB・外部サービス の順に設計する）:

1. `.claude/skills/simple-seed/templates/03_詳細設計/01_ユースケース/UC-{日本語名}.md` を使い、UC ごとに `docs/バックエンド/03_詳細設計/01_ユースケース/UC-{日本語名}.md` を作る
2. DB・外部サービスの仕様が必要なら `docs/バックエンド/03_詳細設計/02_DB・外部サービス/` を作る

### フロントエンド（has_frontend: true のみ）

1. `.claude/skills/frontend-seed/templates/03_詳細設計/01_画面/{カテゴリ名}/{画面名}.md` を使い、カテゴリごとに画面 MD を `docs/フロントエンド/03_詳細設計/01_画面/` に作る
2. `.claude/skills/frontend-seed/templates/03_詳細設計/02_コンポーネント/{コンポーネント名}.md` を使い、共通コンポーネントを `docs/フロントエンド/03_詳細設計/02_コンポーネント/` に作る

各ファイルの `maps_to` に対応コードとテストを必ず入れる。ユーザーに確認・承認を得る。

## Phase 5: architecture contract 化

1. `.spec-runner/architecture/architecture.yaml` を完成させる
2. 現状構造を project 専用 skill へ渡せる粒度に整える
3. `architecture-skill-development` へ引き渡す
