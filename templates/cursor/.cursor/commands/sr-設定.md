# /sr-設定

詳細設定（パス・TDD・DDD 等）を**チャット上で AI が埋める**形で行います。ユースケースは作成しません。

## 重要: 対話はターミナルではなくチャットで行う

- **ターミナルで `init` を実行して入力待ちにしないこと。** AI がプロジェクトを確認し、必要ならチャットでユーザーに聞きながら設定を決め、**AI が** `.spec-runner/config.sh` を編集・生成する。

## 手順

1. `.spec-runner/config.sh` の有無を確認する。ない場合は `npx spec-runner` で一度セットアップされている必要がある（config.sh が存在する前提）。
2. プロジェクト構成（`package.json`、既存の `src/` やテストディレクトリなど）を確認し、以下を決める（不明ならチャットでユーザーに聞く）:
   - Domain / UseCase / Infrastructure のパス
   - テストディレクトリ、ソース・テストの拡張子
   - TDD を必須にするか、DDD を使うか
   - CI プラットフォーム、ドキュメント言語 など
3. **AI が** `.spec-runner/config.sh` を編集または作成する。必ず `export CONFIGURED="true"` を設定し、`sr-初期化` のコマンド説明にある変数（DOMAIN_PATH, USECASE_PATH, TEST_DIR, TDD_ENABLED など）を適切に設定する。
4. 完了したら「設定を config.sh に反映しました。ユースケースを開始する場合は `/sr-初期化 ユースケース名 集約名` を使ってください」と伝える。

**ターミナルで `./.spec-runner/scripts/spec-runner.sh init` を実行して対話に頼る必要はない。**
