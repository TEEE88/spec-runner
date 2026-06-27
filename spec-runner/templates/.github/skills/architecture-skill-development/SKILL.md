---
name: architecture-skill-development
description: architecture contract と docs を読み、プロジェクト専用の skill / rule / template を育てるフロー。
---

# architecture-skill-development

```
Phase 1: 入力確認
Phase 2: 反復フロー抽出
Phase 3: skill / rule / template へ分解
Phase 4: 基盤 skill のプロジェクト固有化
Phase 5: 一貫性検証
Phase 6: セットアップ専用 skill のアーカイブ提案
```

以降の書き換えは全て `architecture.yaml` の `integrations` に従う（`claude` -> `.github/` のみ、`github` -> `.github/` のみ、両方 -> 対で更新）。

## Phase 1: 入力確認

`docs/01_要件定義/` と `.spec-runner/architecture/architecture.yaml` を読み、固定化すべき判断と project 固有判断を切り分ける。

## Phase 2: 反復フロー抽出

よく繰り返す作業を抽出 -> ユーザー承認が必要な箇所を決定 -> 影響調査・TDD 等の共通 skill との接続を決定 -> 承認。

## Phase 3: skill / rule / template へ分解

作成前に `.github/skills/harness-engineering/references/harness-format.md` を読む。

- 会話フロー -> skill / 常時守る約束 -> rule / 毎回コピーする設計書 -> template

### プロジェクト専用スキルの作成

`fullstack-seed` がある場合、作り方をユーザーに確認:

| 選択肢 | 内容 |
|--------|------|
| 新規に作る | `harness-format.md` を基にゼロから記述 |
| リネームだけ | seed をプロジェクト専用名に変更 |
| リネーム＋構成変更 | リネーム後、フェーズ構成・テンプレートパスを実態に合わせる |

seed なし -> 新規に作る。

seed からの作成時は `templates/` を新スキルへコピー（例: `cp -r .github/skills/fullstack-seed/templates/ .github/skills/my-app/templates/`）。不要テンプレート削除・必要分追加 -> 承認。プレースホルダー（`{カテゴリ名}` 等）は残す。seed 本体は Phase 6 まで削除しない。

承認を得て次へ。

## Phase 4: 基盤 skill のプロジェクト固有化

配布された基盤 skill のプレースホルダーを実態に書き換える。

### インフラ構成ファイル

`architecture.yaml` の `language`/`folder_structure`/`testing_policy` を参照:

1. `.gitignore`: 言語固有パターン + プロジェクト固有除外をユーザーと確認して作成
2. `.dockerignore`: `.git`・`docs/`・`tests/`・依存・ビルド成果物を除外。追加除外を確認
3. `Dockerfile.test`: テスト専用イメージ。ベースイメージを確認（例: `python:3.12-slim`）。テスト依存をインストール。`scope: all`/`frontend` ならフロント用も

### test-backend.instructions.md / test-frontend.instructions.md

`test-driven-development` と `run-tests` の参照元。`testing_policy` を参照して書き換え:

1. Docker Compose サービス名（バックエンド・フロント・テスト DB・依存サービス）を確認
2. 起動方針: 必要最小のサービスのみ `docker compose up -d`。順序固定しない
3. 待機方針: healthcheck か接続確認で短い待機。失敗時のみ追加待機
4. テストコマンドを `docker compose run --rm <service> <test-command>` 形式に
5. `down`/`down -v` の使い分け・失敗時 `docker compose logs` を明記。`tests/` 構成が実態と違えば書き換え

### test-driven-development

`language` を参照し、fixture（実クラス名・DB 接続・ヘルパパターン）とモック手段（ライブラリ名）を具体化。

### code-common.instructions.md / code-backend.instructions.md / code-frontend.instructions.md

`scope` で構成を決定:
- `backend` のみ -> code-common 不要、code-backend に全ルール
- `frontend` のみ -> code-common 不要、code-frontend に全ルール
- `all` -> code-common に共通集約、各ファイルは言語固有のみ

書き換え: 命名規則 / 固有の決定事項（言語・フレームワーク・構造） / `<your-*-language-and-type-rules>` を具体ルールに。env var 整合・バックグラウンドタスク耐性など汎用ルールは残す。

### リファレンス URL

`.spec-runner/references/resources.md` に登録。ユーザーに確認: 公式ドキュメント / サンプルリポジトリ / API 仕様（OpenAPI） / 社内 Wiki / ベストプラクティス記事。

### その他

他 skill の同様プレースホルダーも書き換え -> 承認。

## Phase 5: 一貫性検証

既存 skill / rule / agent との矛盾確認。`harness-engineering` が必要な改善点を洗い出す。

**phase-gate**: `node .spec-runner/scripts/scan.js` でエラーなしを確認してから次へ。

## Phase 6: セットアップ専用 skill のアーカイブ提案

開発ループ入り後は不要になる skill を、**ユーザー承認を得てから**整理（自動削除・移動禁止）。

候補: `architecture-definition`（初期化専用）/ `existing-project-to-docs`（取り込み専用）/ `fullstack-seed`（専用スキル作成後）/ このファイル自身（専用 skill 安定後。大変更時は再利用可）

1. 候補提示 -> 承認 -> 削除（`integrations` に従い該当系のみ）
2. `.spec-runner/` 整理: `intake/current-system-inventory.md` は docs 昇格済みなら削除可。`architecture/architecture.yaml` と `scripts/` は**削除しない**（前者は正本、後者は scan/extract/impact が常時依存）
3. グローバル設定（CLAUDE.md / copilot-instructions.md）更新:
   - 「初回自動起動」セクションを削除
   - 「開発ワークフロー」セクションを必ず設け、使う skill を全列挙（skill 記載なし = 未完成）
   - rule は自動適用されるため「○○は△△.md を参照せよ」を書かない（`harness-format.md` 参照）

```markdown
## 開発ワークフロー

作業開始時は必ず対応スキルを使う。スキルなしで実装・設計を進めない。

新機能実装 -> `/feature-development`
既存機能変更 -> `/design-change`
テスト作成 -> `/test-driven-development`
```

## Phase 7: ハーネスエンジニアリング（繰り返し発生した問題がある場合のみ）

このサイクルで skill / rule / template の責務の曖昧さ・重複・不足が**繰り返し**発生した場合は `harness-engineering` で改善する。Phase 5 の一貫性検証で洗い出した改善点が起点になることが多い。1回限りの例外は対象外。
