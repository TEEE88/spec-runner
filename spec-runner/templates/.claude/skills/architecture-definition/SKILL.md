---
name: architecture-definition
description: 新規プロジェクトで docs と `.spec-runner/architecture/architecture.yaml` を立ち上げるための初期化フロー。
---

# architecture-definition

```
Phase 1: 要件整理
Phase 2: フォルダ構造の決定（対話）
Phase 3: アーキテクチャ判断の明文化
Phase 4: architecture contract 作成
Phase 5: architecture-skill-development へ自動移行
```

## Phase 1: 要件整理

1. 背景・提供価値・制約・スコープ外の曖昧点を一問一答で深掘り（推奨回答を添える。コードで確認できることは質問しない）
2. 作成スコープを確認: `all`（両方）/ `backend` / `frontend`
3. バックエンドは DDD スタイル（ドメイン -> UC -> DB・外部サービスの順）で設計する（scope: frontend はスキップ）
4. テンプレートから要件定義を作成: `docs/01_要件定義/要件定義.md`（テンプレート: `.claude/skills/fullstack-seed/templates/01_要件定義/要件定義.md`）。scope に backend があれば `ユビキタス言語辞書.md` も
5. AI 連携を確認: `claude`（`.claude/`）/ `github`（`.github/`）/ 両方
6. 承認を得る

## Phase 2: フォルダ構造の決定

ここで決めた構造がテンプレートの `maps_to` に焼き込まれる -> 概要設計より前に確定させる。

1. 対話で決める: `src/` 構成 / `tests/` 種別構成（`unit/`・`integration/`・`e2e/` 等）/ `docs/` 構成（変える場合）/ IaC・設定等
2. 設計書⇔コードの責務1対1の単位をここで決める（分散・混在禁止）
3. 決定構造を箇条書き提示 -> 承認

## Phase 3: アーキテクチャ判断の明文化

ドメイン分割・責務境界・実装単位・インフラ方針を整理。必要なら ADR 作成（比較案・採用理由は ADR、本文は採用後の仕様のみ）-> 承認。

## Phase 4: architecture contract 作成

`.spec-runner/architecture/architecture.yaml` を作成（補助情報扱い）。最低限:

- `integrations`: Phase 1 の連携
- `scope` / `style: ddd`（frontend のみなら省略可）
- `folder_structure`: Phase 2 の構造
- `domain_structure` / `runtime_units` / `design_policy` / `testing_policy`

承認を得る。

## Phase 5: architecture-skill-development へ自動移行

承認後、コマンドを打たせず続けて開始する:

1. 前提（docs・architecture.yaml・確定構造）を要約
2. project 専用 skill に切り出す反復フローを列挙
3. 確認なしに `architecture-skill-development` Phase 1 へ
4. スキル整備完了後、`fullstack-seed` で概要設計へ
