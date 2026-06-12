---
name: existing-project-to-docs
description: 既存プロジェクトを読み解き、docs の正本と architecture contract を起こすリバース設計フロー。fullstack-seed テンプレートを使用。
---

# existing-project-to-docs

```
Phase 1:   現状把握
Phase 1.5: docs 構成・スコープの合意
Phase 2:   要件定義
Phase 3:   概要設計
Phase 4:   詳細設計
Phase 5:   architecture contract 化
```

## ルール

- docs が正本。全ドキュメントに `spec_runner` ヘッダー。`maps_to` 必須（パス推定禁止）。対応コードとテストを対で入れる
- 設計書1つ = 主要責務1つ。本文にコード・設計記録の内容を書かない
- 既存コードを正として観測する。推測は明示する
- `depends_on` で後続変更に耐える形へ整える
- バックエンドは DDD スタイル（ドメイン -> UC -> DB・外部サービスの順）
- ユーザー承認なしに次フェーズへ進まない
- テンプレートは `.github/skills/fullstack-seed/templates/{相対パス}` を使い、同じ相対パスで `docs/` に作る。詳細設計本文はハイブリッド仕様YAML形式（design-docs.instructions.md）

## Phase 1: 現状把握

1. `src/`・`tests/`・設定ファイル・README・IaC を読む
2. 入口・主要フロー・外部依存を一覧化。フロントエンドの有無を判定
3. `.spec-runner/intake/current-system-inventory.md` を作成 -> 承認

## Phase 1.5: docs 構成・スコープの合意

inventory を元に提案 -> 承認:

- `scope`（all / backend / frontend。backend/frontend は他方の Phase をスキップ）
- `docs/` フォルダ構成・作成予定ファイル一覧

承認後 `.spec-runner/architecture/architecture.yaml` を新規作成し `scope` だけ先に書き込む（残りは Phase 5）。**このスキルから scope 不一致のセクションを削除して最適化する**。

## Phase 2: 要件定義

inventory から既存機能のユースケースを逆算 -> `docs/01_要件定義/要件定義.md`。scope に backend があれば `ユビキタス言語辞書.md` も -> 承認。

## Phase 3: 概要設計

### バックエンド（scope: frontend はスキップ）

`01_システム全体設計/システム俯瞰図.md` -> `システム構成図.md` -> `02_バックエンド/ドメインモデル.md` -> `業務ロジック概要.md` -> `状態遷移図.md` -> 承認。

### フロントエンド（scope: backend はスキップ）

`03_フロントエンド/画面一覧.md` -> `画面遷移図.md` -> `コンポーネント構成.md` -> 承認。

### インターフェース（scope: all のみ）

`04_インターフェース設計/API仕様.md`。外部連携があれば `外部API連携仕様.md` -> 承認。

### ADR（必要時のみ）

設計判断が必要な場合だけ。3案比較 -> 採用案と理由のみ記録。配置・命名は `.github/instructions/design-docs.instructions.md` の ADR テーブル。採用案を概要設計へ反映してから次へ。

## Phase 4: 詳細設計

### バックエンド（scope: frontend はスキップ）

ドメイン -> UC -> DB・外部サービスの順:

- `01_ドメイン/{ドメイン名}.md`（ビジネスルール・集約）
- `02_ユースケース/{カテゴリ名}/UC-{日本語名}.md`
- 必要なら `03_DB・外部サービス/**`

承認を得る。

### フロントエンド（scope: backend はスキップ）

- `01_画面/{カテゴリ名}/{画面名}.md`
- `02_コンポーネント/{カテゴリ名}/{コンポーネント名}.md`（共通コンポーネント）

承認を得る。

## Phase 5: architecture contract 化

1. `.spec-runner/architecture/architecture.yaml` を完成させる
2. 現状構造を project 専用 skill へ渡せる粒度に整え、`architecture-skill-development` へ引き渡す

完了後の継続開発: 既存機能変更 -> `design-change` / 新機能追加 -> プロジェクト専用スキル。
