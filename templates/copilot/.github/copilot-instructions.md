# spec-runner（GitHub Copilot 用指示）

このプロジェクトは **.spec-runner/scripts/spec-runner.sh** によるフェーズゲートで運用している。実装前に必ずフェーズを確認すること。

## 最優先

- 実装コードを書く前に **必ず** `./.spec-runner/scripts/spec-runner.sh status` を実行する。
- `phase` が `implement` でないときは実装コードを生成しない。ユーザーに「現在のフェーズを確認してください」と伝える。
- ユーザーが「init して」「status 確認して」「design-high で進めて」などと言ったら、対応する `./.spec-runner/scripts/spec-runner.sh` をターミナルで実行する。
- スラッシュコマンド `/sr-初期化` などは `.github/prompts/*.prompt.md` に定義済み（コマンド名は日本語）。`tools: [shell]` でシェル実行される。

## TDD（テスト駆動）— デフォルトで有効

- 実装前に **テスト設計ドキュメント** と **テストコード** を必ず書く。テストを先に書いて Red → 実装で Green。
- `.spec-runner/config.sh` の `TDD_ENABLED=false` で無効化すると、テストなしでも implement に進める（オプション）。

## フェーズとコマンド

- require → design-high → design-detail (domain → usecase → table → infra) → test-design → implement
- 各フェーズ完了時: `./.spec-runner/scripts/spec-runner.sh review-pass <該当ファイル>`
- ゲート: `./.spec-runner/scripts/spec-runner.sh set-gate glossary_checked` など
- 実装完了: `./.spec-runner/scripts/spec-runner.sh complete`
- 修正: `./.spec-runner/scripts/spec-runner.sh fix "内容"` / `./.spec-runner/scripts/spec-runner.sh hotfix "内容"`

詳細はプロジェクトの README を参照。
