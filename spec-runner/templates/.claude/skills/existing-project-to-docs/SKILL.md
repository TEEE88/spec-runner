---
name: existing-project-to-docs
description: 既存プロジェクトを読み解き、docs の正本と architecture contract を起こすリバース設計フロー。fullstack-seed テンプレートを使用。
---

# existing-project-to-docs

## 全体フロー

```
Phase 1:   現状把握
Phase 1.5: docs 構成・スコープの合意
Phase 2:   要件定義
Phase 3:   概要設計
Phase 4:   詳細設計
Phase 5:   architecture contract 化
```

## スコープの確認

開始前にユーザーにリバース設計の対象スコープを確認する:

| scope | 意味 |
|-------|------|
| `all` | バックエンド・フロントエンドを両方リバース設計（デフォルト） |
| `backend` | バックエンドのみ。フロントエンドの Phase はスキップ |
| `frontend` | フロントエンドのみ。バックエンドの Phase はスキップ |

確認後、`scope` を architecture.yaml に書き込み、**このスキルファイルから scope 条件に合わないセクション（`scope: XX の場合はスキップ` と注釈されたセクション）を削除して最適化する**。

## 前提ルール

- docs は正本とし、各ドキュメントに `spec_runner` ヘッダーを付ける
- `maps_to` は必ず設定する。パス推定に頼らない
- 設計書本文にはコードを書かない。コード片・DDL・クラス定義は `src/` / `tests/` に置く
- 設計書本文に設計記録の内容を書かない。比較案・採用理由・判断経緯は設計記録に分離する
- 設計書とコードは責務が 1 対 1 で対応するように分割する
- 既存コードを正として観測する。推測する場合は明示する
- `depends_on` を使って後続変更に耐える形へ整える
- ユーザー承認なしに次フェーズへ進めない
- バックエンドは常に DDD スタイル（ドメイン → UC → DB・外部サービスの順）で設計する

## Phase 1: 現状把握

1. `src/`、`tests/`、設定ファイル、README、IaC を読む
2. 現状システムの入口、主要フロー、外部依存を一覧化する
3. フロントエンドの有無（Web UI・画面があるか）を判定する
4. `.spec-runner/intake/current-system-inventory.md` を作る
5. ユーザーに確認・承認を得る

## Phase 1.5: docs 構成・スコープの合意

ファイルを作成する前に、docs の構成をユーザーと合意する。

1. `current-system-inventory.md` を元に以下を提案する:
   - 確定した `scope`（`all` / `backend` / `frontend`）
   - `docs/` のフォルダ構成
   - 作成予定ファイルの一覧
2. ユーザーに確認・承認を得る
3. 承認後、`.spec-runner/architecture/architecture.yaml` を新規作成し `scope` だけ先に書き込む（残りは Phase 5 で完成させる）

## Phase 2: 要件定義

1. `current-system-inventory.md` を起点に、既存機能からユースケースを逆算する
2. `.github/skills/fullstack-seed/templates/01_要件定義/要件定義.md` を使い `docs/01_要件定義/要件定義.md` を作る
3. `scope: all` または `scope: backend` の場合: ドメイン用語が識別できたら `.github/skills/fullstack-seed/templates/01_要件定義/ユビキタス言語辞書.md` を使い `docs/01_要件定義/ユビキタス言語辞書.md` を作る
4. ユーザーに確認・承認を得る

## Phase 3: 概要設計

### バックエンド概要設計（scope: frontend の場合はスキップ）

1. `.github/skills/fullstack-seed/templates/02_概要設計/01_システム全体設計/システム俯瞰図.md` を使い `docs/02_概要設計/01_システム全体設計/システム俯瞰図.md` を作る
2. `.github/skills/fullstack-seed/templates/02_概要設計/01_システム全体設計/システム構成図.md` を使い `docs/02_概要設計/01_システム全体設計/システム構成図.md` を作る
3. `.github/skills/fullstack-seed/templates/02_概要設計/02_バックエンド/ドメインモデル.md` を使い `docs/02_概要設計/02_バックエンド/ドメインモデル.md` を作る
4. `.github/skills/fullstack-seed/templates/02_概要設計/02_バックエンド/業務ロジック概要.md` を使い `docs/02_概要設計/02_バックエンド/業務ロジック概要.md` を作る
5. `.github/skills/fullstack-seed/templates/02_概要設計/02_バックエンド/状態遷移図.md` を使い `docs/02_概要設計/02_バックエンド/状態遷移図.md` を作る
6. ユーザーに確認・承認を得る

### フロントエンド概要設計（scope: backend の場合はスキップ）

1. `.github/skills/fullstack-seed/templates/02_概要設計/03_フロントエンド/画面一覧.md` を使い `docs/02_概要設計/03_フロントエンド/画面一覧.md` を作る
2. `.github/skills/fullstack-seed/templates/02_概要設計/03_フロントエンド/画面遷移図.md` を使い `docs/02_概要設計/03_フロントエンド/画面遷移図.md` を作る
3. `.github/skills/fullstack-seed/templates/02_概要設計/03_フロントエンド/コンポーネント構成.md` を使い `docs/02_概要設計/03_フロントエンド/コンポーネント構成.md` を作る
4. ユーザーに確認・承認を得る

### インターフェース設計（scope: all の場合のみ）

1. `.github/skills/fullstack-seed/templates/02_概要設計/04_インターフェース設計/API仕様.md` を使い `docs/02_概要設計/04_インターフェース設計/API仕様.md` を作る
2. 外部連携がある場合: `.github/skills/fullstack-seed/templates/02_概要設計/04_インターフェース設計/外部API連携仕様.md` を使い `docs/02_概要設計/04_インターフェース設計/外部API連携仕様.md` を作る
3. ユーザーに確認・承認を得る

### ADR（必要時のみ）

1. 設計判断が必要な場合だけ ADR を作る
2. 提案時に必ず 3 案を比較する。ドキュメントには採用案と採用理由のみ記録する
3. ファイル名は `mmdd-{日本語タイトル}.md`、配置先は `.github/instructions/design-docs.instructions.md` の「ADR 配置ルール」を参照
4. 採用案を概要設計へ反映してから次へ進む

## Phase 4: 詳細設計

### バックエンド詳細設計（scope: frontend の場合はスキップ）

ドメイン → UC → DB・外部サービス の順に設計する。

1. `.github/skills/fullstack-seed/templates/03_詳細設計/01_バックエンド/01_ドメイン/{ドメイン名}.md` を使い、ドメインごとにビジネスルール・集約を整理し `docs/03_詳細設計/01_バックエンド/01_ドメイン/{ドメイン名}.md` を作る
2. `.github/skills/fullstack-seed/templates/03_詳細設計/01_バックエンド/02_ユースケース/{カテゴリ名}/UC-{日本語名}.md` を使い、カテゴリごとに `docs/03_詳細設計/01_バックエンド/02_ユースケース/{カテゴリ名}/UC-{日本語名}.md` を作る（シーケンス図は Mermaid で埋め込む）
3. DB・外部サービスの仕様が必要なら `.github/skills/fullstack-seed/templates/03_詳細設計/01_バックエンド/03_DB・外部サービス/` を参照して `docs/03_詳細設計/01_バックエンド/03_DB・外部サービス/` を作る
4. ユーザーに確認・承認を得る

### フロントエンド詳細設計（scope: backend の場合はスキップ）

画面 → コンポーネント の順に設計する。

1. `.github/skills/fullstack-seed/templates/03_詳細設計/02_フロントエンド/01_画面/{カテゴリ名}/{画面名}.md` を使い、カテゴリごとに `docs/03_詳細設計/02_フロントエンド/01_画面/{カテゴリ名}/{画面名}.md` を作る
2. `.github/skills/fullstack-seed/templates/03_詳細設計/02_フロントエンド/02_コンポーネント/{カテゴリ名}/{コンポーネント名}.md` を使い、共通コンポーネントを `docs/03_詳細設計/02_フロントエンド/02_コンポーネント/` に作る
3. ユーザーに確認・承認を得る

---

各ファイルの `maps_to` に対応コードとテストを必ず対で入れる。1 つの設計書には 1 つの主要責務だけを書き、その責務を実装するコードとテストに対応させる。

## Phase 5: architecture contract 化

1. `.spec-runner/architecture/architecture.yaml` を完成させる
2. 現状構造を project 専用 skill へ渡せる粒度に整える
3. `architecture-skill-development` へ引き渡す

`architecture-skill-development` 完了後の継続開発:
- 既存機能の変更 → `design-change` スキルを使う
- 新機能の追加 → プロジェクト専用スキルを使う
