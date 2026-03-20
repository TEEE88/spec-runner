# 設計ドキュメント

このサイトは **MkDocs Material** で、プロジェクトの `docs/` 配下にある **憲章・設計書・仕様** をまとめて閲覧するためのものです。

## spec-runner との対応（既定パス）

| 領域 | パス（プロジェクトルートから） |
|------|------------------------------|
| 憲章 | `docs/01_憲章/憲章.md` |
| ユースケース仕様 | `docs/02_ユースケース仕様/` |
| ドメイン設計 | `docs/03_ドメイン設計/` |
| アーキテクチャ | `docs/04_アーキテクチャ/` |
| インフラ設計 | `docs/05_インフラ設計/` |
| API 仕様 | `docs/06_API仕様/` |

手順・コマンド・ロックの考え方は、リポジトリの `docs/flow.md` を参照してください。

---

## プレビュー起動

リポジトリルートで次を実行します（Python 3 と `requirements-docs.txt` 用の仮想環境 `.venv-docs/` が使われます）。

```bash
python3 -m venv .venv-docs && ./.venv-docs/bin/pip install -q -r requirements-docs.txt && ./.venv-docs/bin/mkdocs serve --dev-addr 127.0.0.1:8000
```

`8000` 番が使用中の場合はポートを変えられます。

```bash
python3 -m venv .venv-docs && ./.venv-docs/bin/pip install -q -r requirements-docs.txt && ./.venv-docs/bin/mkdocs serve --dev-addr 127.0.0.1:8001
```
