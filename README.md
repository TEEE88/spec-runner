# spec-runner

フェーズ駆動で設計を飛ばさないようにする仕組み。`npx spec-runner` でプロジェクトに `.spec-runner/` を入れ、**次のステップ** を 1 本だけ返すコマンドに従って進める。

---

## インストール

```bash
npx spec-runner
```

または:

```bash
curl -sSL https://raw.githubusercontent.com/TEEE88/spec-runner/main/install.sh | bash
```

いずれも、プロジェクト直下に `.spec-runner/` ができる。

あわせて、**未有効時のみ**プロジェクトルートに次が配置される（Material for MkDocs で `docs/` 配下の設計書をプレビューするため）。

- `mkdocs.yml` / `requirements-docs.txt`
- `docs/index.md`（サイトのホーム）

`.spec-runner/` がすでにあり **2 回目以降はエラーで止まる** 場合も、**その手前**で上記 MkDocs 用ファイルの不足分だけ補完される（初回導入以前のリポジトリで MkDocs だけ足したいときに便利）。

---

## 使い方

1. プロジェクトルートで次を実行する。

   ```bash
   ./.spec-runner/spec-runner.sh 次のステップ --json
   ```

2. 出力の `command_file` に書いてある `.spec-runner/steps/*.md` を開き、その指示に従って作業する。

3. 作業が終わったら、再度 1 を実行する。次のステップが返る。

AI から使う場合は、`/spec-runner` のように「spec-runner を実行する」と伝えればよい。フェーズやコマンド名を覚える必要はない。

**Git**: フェーズごとにブランチを切る必要はない。**コミットしたくなったとき**に、AI と `project.json` の命名に沿ってブランチ名・メッセージを相談し、一緒にコミットする運用でよい（詳細は同梱の `docs/flow.md` と `.spec-runner/steps/仕様策定.md`）。

---

## フロー（全体像）

設計書（`docs/01..06`）と UC 仕様（`docs/02_ユースケース仕様/`）をどんな順で作っていくかは `docs/flow.md` にまとめています。

## Skills テンプレート（任意）

- `templates/skills/uc-k1-work-card-init/SKILL.md`（`docs/work.md` 初期化）
- `templates/skills/uc-k2-pre-commit-check/SKILL.md`（コミット前チェック案内）
- `templates/skills/uc-k3-spec-impl-diff-review/SKILL.md`（仕様-実装差分レビュー）
- `npx spec-runner` 実行時に、不足分のみ `.claude/skills/` へ自動コピーされます（既存ファイルは上書きしない）。

---

## ドキュメントサイト（MkDocs + Material）

### `npx spec-runner` したプロジェクト側

憲章・設計書は `steps.json` どおり `docs/01_憲章/` 〜 `docs/06_API仕様/` に置かれる。`mkdocs.yml` の `docs/` がそのままサイトの文書ルートになるので、**追加コピーなしで**これらの Markdown をナビに載せられる（`nav` で先頭に固定した `index.md` の後ろへ、残りのページが自動で続く）。

プレビュー起動（Python 3 必須・仮想環境 `.venv-docs/` を使用）:

```bash
python3 -m venv .venv-docs && ./.venv-docs/bin/pip install -q -r requirements-docs.txt && ./.venv-docs/bin/mkdocs serve --dev-addr 127.0.0.1:8000
```

`8000` が使用中のとき:

```bash
python3 -m venv .venv-docs && ./.venv-docs/bin/pip install -q -r requirements-docs.txt && ./.venv-docs/bin/mkdocs serve --dev-addr 127.0.0.1:8001
```

## 導入後にできるもの

```
<プロジェクトルート>/
├── .spec-runner/
│   ├── spec-runner.sh          # 入口（次のステップ --json）
│   ├── project.json            # 設定（ブランチ命名・必須ドキュメント・テストコマンド等）
│   ├── phase-locks.json        # フェーズの通過状態
│   ├── scripts/                # spec-runner-core.sh, check, branch 等
│   ├── steps/                  # 憲章・ドメイン設計・仕様策定・曖昧さ解消・テスト設計・実装 等の .md
│   └── templates/              # UC 仕様書ひな形
├── .claude/commands/spec-runner.md   # Claude 用コマンド定義（/spec-runner）
├── .claude/skills/                   # Skills テンプレート（不足分のみ自動配置）
├── mkdocs.yml                 # MkDocs（未有効時のみ配置）
├── requirements-docs.txt      # mkdocs / mkdocs-material（未有効時のみ配置）
├── docs/                      # 設計書（01..06）＋ work.md ＋ index.md 等。MkDocs の文書ルート
└── （AI は Claude Code 前提）
```

---

## 必要環境

- Node.js 16+
- jq
- git
- bash 4.0+
- 設計書の MkDocs プレビュー: Python 3（venv + mkdocs コマンドを直接実行）

---

## 上書きインストール

すでに `.spec-runner/` があるときは上書きしない。上書きしたい場合:

```bash
SPEC_RUNNER_FORCE=1 npx spec-runner
```

---

## バージョン運用ルール

- このリポジトリでは、今後 **コミットごとに `package.json` の `version` を更新**する。
- バージョンは原則として SemVer に従い、迷う場合はパッチ（`x.y.Z`）を 1 つ上げる。
- 1コミット内で複数の変更をまとめた場合も、コミット単位で 1 回だけ更新する。

---

## ライセンス

MIT
