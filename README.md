# spec-runner — AI-driven DDD Phase Gate System

AI が設計を飛ばして実装に入るのを、**シェルとゲートで防ぐ**フェーズゲート。Claude Code / Cursor / GitHub Copilot 対応。

---

## 新規開発の流れ（最初から）

### 1. やりたいことを AI に相談する

Cursor や Claude で「〇〇がしたい」と話す。

### 2. AI がフォルダ構造を提案し、人が OK する

AI が次のような案を出す：

- 使用フレームワーク・言語
- 拡張子
- 各レイヤーの**ルートパス**（Domain / UseCase / Infrastructure）
- マイグレーションのディレクトリ
- テストのディレクトリ
- 必要ならサブフォルダ案（例: UseCase を `会員登録/` `注文/` で分ける）

人が「それで」と OK した時点で、**パスが決まった**状態になる。

### 3. spec-runner を入れる

```bash
npx spec-runner
```

対話では**どの開発環境か**だけ聞かれる（AI ツール・CI・ドキュメント言語）。  
ここまでで、`.spec-runner/config.sh`（既定値）と `scripts/`・`docs/`・`.github/` などができる。

### 4. init で詳細設定と最初のユースケースを開始する

```bash
./scripts/spec-runner.sh init "会員登録" "会員"
```

**init を実行すると対話が始まる**（初回のみ）。AI と相談して決めた次の内容を入力する：

- 使用フレームワーク・言語（メモ用・任意）
- Domain / UseCase / Infrastructure のパス
- マイグレーション・テストディレクトリ、ソース拡張子
- Domain が import してはいけないパターン（正規表現）
- DDD を使うか / TDD を必須にするか / CI / ドキュメントの言語

設定後、`docs/requirements/会員登録.md` ができ、ブランチ `feature/uc-会員登録` が作られる。

- 引数なしで `./scripts/spec-runner.sh init` だけ実行すると、**設定対話のみ**（ユースケースは作らない）。
- すでに設定済みの場合は対話をスキップし、そのままユースケース作成に進む。

### 5. 開発フロー（この順で進める）

```
① 要件定義
   docs/requirements/会員登録.md を書く

② 要件レビュー通過
   ./scripts/spec-runner.sh review-pass docs/requirements/会員登録.md
   ./scripts/spec-runner.sh set-gate glossary_checked

③ 概要設計
   ./scripts/spec-runner.sh design-high
   docs/high-level/会員登録.md を書く → review-pass

④ 詳細設計（この順）
   ./scripts/spec-runner.sh design-detail domain   → domain.md を書く → review-pass
   ./scripts/spec-runner.sh design-detail usecase  → usecase.md を書く → review-pass
   ./scripts/spec-runner.sh design-detail table    → table.md を書く → review-pass
   ./scripts/spec-runner.sh design-detail infra   → infra.md を書く → review-pass

⑤ テスト設計
   ./scripts/spec-runner.sh test-design
   docs/test-design/会員登録.md を書く
   テストコードを先に書く（Red）→ コミット
   ./scripts/spec-runner.sh set-gate test_code_committed
   ./scripts/spec-runner.sh review-pass docs/test-design/会員登録.md

⑥ 実装
   ./scripts/spec-runner.sh implement
   テストを Green にする実装を書く

⑦ 完了
   ./scripts/spec-runner.sh complete
```

TDD はデフォルトで有効。実装に進むには「テスト設計ドキュメント」と「テストコードのコミット」が必須。無効にしたいときは `.spec-runner/config.sh` で `export TDD_ENABLED="false"`。

### 6. PR とマージ

`git push` して PR。`.github/workflows/phase-gate-check.yml` がドキュメントとパスの整合をチェックする。

---

## インストール方法

```bash
npx spec-runner
```

または:

```bash
curl -sSL https://raw.githubusercontent.com/spec-runner/spec-runner/main/install.sh | bash
```

[Use this template](https://github.com/spec-runner/spec-runner/generate) からリポジトリを作る方法もある。

---

## 強制の仕組み（3層）

| 層 | 内容 |
|----|------|
| **1. spec-runner.sh** | 各コマンドで「必要なドキュメント・ゲート」をチェック。足りないと先に進めない。 |
| **2. 実装前ブロック** | Claude Code は `.claude/hooks` で implement 以外のコード出力をブロック。Cursor / Copilot は `.cursorrules` 等で「status で phase を確認し、implement でないときはコードを書かない」とルール指定。 |
| **3. CI** | `.github/workflows/phase-gate-check.yml` が PR 時にドキュメント鮮度・DDD 依存方向などをチェック。 |

---

## 設定

`.spec-runner/config.sh` でパスやコマンドを変えられる。CI とゲートはこの設定を参照する。

- `DOMAIN_PATH` / `USECASE_PATH` / `INFRA_PATH` … 各レイヤーの**ルート**。その下のサブフォルダ（UseCase 内の `会員登録/` など）は自由。強制したいルールは `.cursorrules` や `CLAUDE.md` に書く。
- `TEST_DIR` … テストの置き場所。TDD 時の「未コミット検出」に使う。
- `TDD_ENABLED` … `false` にすると、テストなしでも implement に進める。

---

## 導入後に増えるもの

```
<プロジェクトルート>/
├── .spec-runner/
│   ├── config.sh       # パス・拡張子・TDD 等
│   └── state.json      # 現在のフェーズ（gitignore 推奨）
├── .github/
│   ├── workflows/phase-gate-check.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/                # 要件・概要・詳細設計・テスト設計
├── scripts/spec-runner.sh
└── templates/requirement/template.md
```

選択した AI ツールに応じて `.claude/` や `.cursorrules` や `.github/copilot-instructions.md` などが追加される。

---

## アップデート

```bash
npx spec-runner --update
```

`scripts/spec-runner.sh` と `.claude/hooks/` が更新される。ドキュメントや config は上書きしない。

---

## スラッシュコマンド

**`/sr-status` を実行すると、現在のフェーズと「次にやるべきこと」（次に打つコマンド）が動的に表示される。** フェーズ移行（概要設計〜実装完了）はこの案内に従えばよい。

| コマンド | 説明 |
|----------|------|
| `/sr-configure` | 詳細設定の対話のみ |
| `/sr-init` [ユースケース名] [集約名] | ユースケース開始（未設定時は対話から） |
| `/sr-status` | フェーズ・ゲート＋**次にやるべきこと**を表示 |
| `/sr-review` ファイル | レビュー通過 |
| `/sr-set-gate` ゲート名 | ゲート手動通過 |
| `/sr-fix` 内容 | 修正 |
| `/sr-hotfix` 内容 | 緊急修正 |

design-high / design-detail / test-design / implement / complete は、status の案内に表示されるので個別に指定不要。

定義: Claude `.claude/commands/` / Cursor `.cursor/commands/` / Copilot `.github/prompts/*.prompt.md`

---

## 必要環境

- Node.js 16+
- jq
- git
- bash 4.0+

---

## ライセンス

MIT
