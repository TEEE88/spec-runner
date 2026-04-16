---
name: architecture-skill-development
description: architecture contract と docs を読み、プロジェクト専用の skill / rule / template を育てるフロー。
---

# architecture-skill-development

## 全体フロー

```
Phase 1: 入力の確認
Phase 2: 反復フローの抽出
Phase 3: skill / rule / template へ分解
Phase 4: 基盤 skill のプロジェクト固有化
Phase 5: 一貫性の検証
Phase 6: セットアップ専用 skill のアーカイブ提案
```

## Phase 1: 入力の確認

1. `docs/バックエンド/01_要件定義/**` を読む。`has_frontend: true` の場合は `docs/フロントエンド/01_要件定義/**` も読む
2. `.spec-runner/architecture/architecture.yaml` を読む
3. 固定化すべき判断と project 固有判断を切り分ける

## Phase 2: 反復フローの抽出

1. よく繰り返す作業を抽出する
2. どこにユーザー承認が必要かを決める
3. 影響調査や TDD など共通 skill をどうつなぐか決める
4. ユーザーに確認・承認を得る

## Phase 3: skill / rule / template へ分解

ファイルを作成する前に `.claude/skills/harness-engineering/references/harness-format.md` を読み、フォーマットを確認する。

1. 会話フローは skill にする
2. 常時守る約束は rule にする
3. 毎回コピーする設計書は template にする

### プロジェクト専用スキルの作成

`architecture.yaml` の `style` に応じた seed（`ddd-seed` / `simple-seed`）がインストール済みの場合、どのように専用スキルを作るかをユーザーに確認する。

| 選択肢 | 内容 |
|--------|------|
| 新規に作る | `harness-format.md` を基に、このプロジェクトのフローをゼロから記述する |
| リネームだけ | seed ファイルをプロジェクト専用名に変更する |
| リネーム＋構成変更 | seed をリネームしたうえでフェーズ構成・テンプレートパスをプロジェクトの実態に合わせて書き換える |

seed が存在しない場合は「新規に作る」で進める。

`has_frontend: true` の場合は、`frontend-seed` と バックエンド seed の両方を並走させる旨を専用スキルに明記する。

### テンプレートの移行

seed からスキルを作成した場合（リネーム・リネーム＋構成変更）、seed の `templates/` を新しいスキルの `templates/` にそのままコピーする。

```
# 例: ddd-seed → my-feature の場合
cp -r .claude/skills/ddd-seed/templates/ .claude/skills/my-feature/templates/
```

コピー後、このプロジェクトで不要なテンプレートファイルを削除し、必要なテンプレートファイルを追加してユーザーに承認を得る。プレースホルダー（`{カテゴリ名}` 等）はそのまま残す。

`integrations` に従い `.claude/` / `.github/` 両系で同様に実施する。seed 本体は Phase 6 でアーカイブするまで削除しない。

4. ユーザーに確認・承認を得る

## Phase 4: 基盤 skill のプロジェクト固有化

インストール時に配布された基盤 skill のプレースホルダーを、このプロジェクトの実態に書き換える。
以降の書き換えはすべて `architecture.yaml` の `integrations` に従う（`claude` のみなら `.claude/` だけ、`github` のみなら `.github/` だけ、両方なら対で更新する）。

### インフラ構成ファイルの整備

`architecture.yaml` の `language` / `folder_structure` / `testing_policy` を参照して以下を作成する。

1. **`.gitignore`**: 言語・フレームワーク固有のパターン（依存パッケージ・ビルド成果物・キャッシュ）と、プロジェクト固有の除外パス（`.env`、`docs/` 等）をユーザーと確認して作成する
2. **`.dockerignore`**: `.git`・`docs/`・`tests/`・依存パッケージ・ビルド成果物をビルドコンテキストから除外する。ユーザーに追加除外パスを確認する
3. **`Dockerfile.test`**: テスト実行専用イメージを作成する
   - ベースイメージをユーザーに確認する（例: `python:3.12-slim`, `node:20-alpine`）
   - テスト依存（テストフレームワーク・カバレッジツール等）をインストールする
   - `has_frontend: true` の場合はフロントエンド用も作成する

### test-config.md の書き換え

`rules/test-config.md`（GitHub Copilot は `instructions/test-config.instructions.md`）はテスト実行コマンドの単一ソースとして `test-driven-development` スキルと `run-tests` エージェントの両方から参照される。`architecture.yaml` の `testing_policy` を参照して書き換える。

1. **Docker Compose サービス名の確認**: バックエンド・フロントエンドそれぞれのサービス名をユーザーに確認する（例: `backend`, `frontend`）
2. **LocalStack の確認**: AWS サービスを使うか確認する。使う場合は対象サービス（S3, SQS, DynamoDB 等）と LocalStack のサービス名をユーザーに確認する
3. **テスト実行コマンド**: `docker compose run --rm <service> <test-command>` の形式で各コマンドを書き換える
4. **テスト構成**: `tests/` のディレクトリ構成が実態と異なる場合は書き換える

### test-driven-development の書き換え

`architecture.yaml` の `language` を参照して、以下を実際の値に置き換える。

1. **fixture / テストデータ**: このプロジェクトの実際のクラス名・DB 接続方法・ヘルパ関数パターンを記述する
2. **モックのルール**: 使用する外部サービスとモック手段（ライブラリ名など）を具体化する

### code-style.md の書き換え

`architecture.yaml` の `language` と `folder_structure` を参照して、以下を実際の値に置き換える。

1. **命名規則**: 言語の慣習に合わせてテーブルの規則・例を書き換える
2. **コメント規約**: `## コメント` の「プロジェクト固有の決定事項」をユーザーと合意してから書き換える
   - インラインコメント（なぜ）・処理ブロック（何）・docコメント・TODO/FIXME・セクション区切りの各方針を決定する
3. **言語・型固有ルール**: `<your-language-and-type-rules>` を言語・フレームワークに合わせた具体的なルールに書き換える
4. **プロジェクト構造**: `<your-project-structure>` を `folder_structure` の実際のディレクトリ構成に書き換える

### リファレンス URL の登録

`.spec-runner/references/resources.md` に、このプロジェクトで使う公式ドキュメントの URL を登録する。

1. ユーザーに以下を確認する:
   - 言語・フレームワーク・ツールの公式ドキュメント URL
   - 参考にしているサンプルリポジトリ・リファレンス実装
   - API 仕様（OpenAPI など）
   - 社内 Wiki・Notion などの内部ドキュメント
   - その他ベストプラクティス記事・移行ガイドなど
2. 教えてもらった情報を名前・カテゴリとともに `.spec-runner/references/resources.md` の該当テーブルに書き込む
3. ユーザーが追加を終えたら次へ進む

### その他の基盤 skill

同様のプレースホルダーや汎用記述が他の skill にあれば、同じ要領で書き換える。

5. ユーザーに確認・承認を得る

## Phase 5: 一貫性の検証

1. 既存 skill / rule / agent と矛盾しないか確認する
2. `harness-engineering` が必要な改善点を洗い出す

## Phase 6: セットアップ専用 skill のアーカイブ提案

セットアップ時にしか使わない skill は、開発ループに入ると不要になる。ユーザーの承認を得てから整理する。絶対に自動で削除・移動しない。

### アーカイブ候補

| skill | 理由 |
|---|---|
| `architecture-definition` | 新規プロジェクト初期化専用。アーキテクチャ確定後は不要 |
| `existing-project-to-docs` | 既存プロジェクト取り込み専用。docs 生成後は不要 |
| `ddd-seed` / `simple-seed` | プロジェクト専用スキル作成後は不要 |
| `frontend-seed` | `has_frontend: true` かつプロジェクト専用スキル作成後は不要 |
| `architecture-skill-development`（このファイル自身） | project 専用 skill が安定したら不要。アーキテクチャ大変更時は再利用可 |

### 手順

1. 上記の候補をユーザーに提示し、整理してよいか確認する
2. 承認を得た skill を削除する（`integrations` に従い `.claude/skills/` / `.github/skills/` の該当するほうを削除する）
3. 必要であれば削除前にバックアップ先をユーザーに伝える
4. `.spec-runner/` の不要ファイルも整理する
   - `intake/current-system-inventory.md` — docs に昇格済みなら削除してよい
   - `architecture/architecture.yaml` — **削除しない**。設計変更のたびに最新状態を保つ。プロジェクトの全体像を把握するための正本として使い続ける
   - `scripts/scan.js` — **削除しない**。`@analyze-impact` が常時依存しているため
5. `CLAUDE.md` を更新する
   - 「初回自動起動」セクション（spec-runner インストール時に生成されたもの）を削除する
   - **必ず「開発ワークフロー」セクションを設け、各作業でどの skill を使うかを全て明記する。** skill の記載がない CLAUDE.md は未完成とみなす
   - 以下のフォーマットをベースに、このプロジェクトで使う skill を全て列挙する:
     ```markdown
     ## 開発ワークフロー

     作業を開始するときは必ず対応するスキルを使うこと。スキルなしで直接実装・設計を進めてはならない。

     新機能を実装するときは `/feature-development` を使う。
     既存機能を変更するときは `/design-change` を使う。
     テストを書くときは `/test-driven-development` を使う。
     ```
   - `.claude/` と `.github/` 両系で内容が変わる場合は、それぞれに反映する
