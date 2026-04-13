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

1. `docs/01_要件定義/**` を読む
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

### seed の選択

`architecture.yaml` の `style` と `has_frontend` を読み、使う seed を決める。

| style | 使う seed | 説明 |
|-------|----------|------|
| `ddd` | `ddd-seed` | ドメイン層（集約・値オブジェクト）を持つ DDD 向けフロー |
| `layered` | `simple-seed` | ドメイン層を持たない UC・サービス層中心のフロー |

`has_frontend: true` の場合、seed から生成するプロジェクト専用スキルに「UC ファイルに画面レイアウトセクションを含める」旨を明記する。

選んだ seed の SKILL.md をコピーし、フェーズ構成・テンプレートパス・用語をこのプロジェクトの実態に合わせて書き換えたプロジェクト専用 skill を作る（Phase 1 は完了済みのため削除する。元の seed はアーカイブ候補とする）。

4. ユーザーに確認・承認を得る

## Phase 4: 基盤 skill のプロジェクト固有化

インストール時に配布された基盤 skill のプレースホルダーを、このプロジェクトの実態に書き換える。
以降の書き換えはすべて `architecture.yaml` の `integrations` に従う（`claude` のみなら `.claude/` だけ、`github` のみなら `.github/` だけ、両方なら対で更新する）。

### test-config.md の書き換え

`rules/test-config.md`（GitHub Copilot は `instructions/test-config.instructions.md`）はテスト実行コマンドの単一ソースとして `test-driven-development` スキルと `run-tests` エージェントの両方から参照される。`architecture.yaml` の `testing_policy` を参照して書き換える。

1. **テスト実行コマンド**: `<your-unit-test-command>` / `<your-integration-test-command>` 等を実際のコマンドに書き換える
2. **テスト構成**: `tests/` のディレクトリ構成が実態と異なる場合は書き換える

### test-driven-development の書き換え

`architecture.yaml` の `language` を参照して、以下を実際の値に置き換える。

1. **fixture / テストデータ**: このプロジェクトの実際のクラス名・DB 接続方法・ヘルパ関数パターンを記述する
2. **モックのルール**: 使用する外部サービスとモック手段（ライブラリ名など）を具体化する

### 影響範囲チェックリストの書き換え

`.claude/skills/design-change/references/影響範囲チェックリスト.md` をプロジェクト固有の変更カテゴリとパスに合わせて書き換える。

1. 変更カテゴリをプロジェクトの構成要素（モジュール・サービス・ドメインなど）に合わせて追加・削除する
2. 詳細設計のパスを `architecture.yaml` の `folder_structure` に合わせて書き換える

### code-style.md の書き換え

`architecture.yaml` の `language` と `folder_structure` を参照して、以下を実際の値に置き換える。

1. **命名規則**: 言語の慣習に合わせてテーブルの規則・例を書き換える
2. **コメント規約**: `## コメント` の「プロジェクト固有の決定事項」をユーザーと合意してから書き換える
   - インラインコメント（なぜ）・処理ブロック（何）・docコメント・TODO/FIXME・セクション区切りの各方針を決定する
3. **言語・型固有ルール**: `<your-language-and-type-rules>` を言語・フレームワークに合わせた具体的なルールに書き換える
4. **プロジェクト構造**: `<your-project-structure>` を `folder_structure` の実際のディレクトリ構成に書き換える

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
| `ddd-seed` | style: ddd で seed 使用後は不要。ただし `architecture-definition` も同時アーカイブする場合のみ `templates/01_要件定義/` を削除可 |
| `simple-seed` | style: layered で seed 使用後は不要 |
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
   - 作成した project 専用 skill の名前と使いどころを記載する
   - 例:
     ```markdown
     ## 開発ワークフロー
     新機能を実装するときは `/feature-development` を使う。
     既存機能を変更するときは `/design-change` を使う。
     テストを書くときは `/test-driven-development` を使う。
     ```
   - `.claude/` と `.github/` 両系で内容が変わる場合は、それぞれに反映する
