# /sr-初期化

**チャットで使うコマンド**。ユーザーが `/sr-初期化` の後に続けて入力した文字列を引数として扱います（例: `/sr-初期化 Todoアプリ` → ユースケース名「Todoアプリ」）。

## 重要: 対話は「チャット上で AI が埋める」形式で行う

- **ターミナルで read や npx --configure の入力待ちにしないこと。** 未設定時は、**AI が** プロジェクト構成を確認し、必要ならチャットでユーザーに聞きながら設定を決め、**AI が** `.spec-runner/config.sh` を編集・生成してから init を実行する。

## 手順

1. **設定済みか確認**  
   `.spec-runner/config.sh` が存在し、かつ `CONFIGURED="true"` かどうかを確認する。

2. **未設定の場合（config.sh がない、または CONFIGURED が true でない）**
   - プロジェクトの `package.json` や既存の `src/` などを確認し、Domain/UseCase/テストのパスなどを推測する。
   - 必要ならチャットでユーザーに聞く（例: 「Domain のパスは `src/domain` でよさそうですが、変更しますか？」）。
   - 決まったら **AI が** `.spec-runner/config.sh` を編集または作成する。必ず `export CONFIGURED="true"` を設定し、以下の変数も設定する（既存の config.sh がある場合は必要な部分だけ上書きする）。
   - その後、ターミナルで `./.spec-runner/scripts/spec-runner.sh init <引数>` を実行する。このときはすでに CONFIGURED が true なので、ターミナルでの対話は発生しない。

3. **設定済みの場合**  
   そのまま `./.spec-runner/scripts/spec-runner.sh init <ユーザーが入力した引数>` を実行する。

4. **引数がない場合**  
   ユーザーに「ユースケース名（と任意で集約名）を指定してください」と伝えるか、設定だけしたい場合は `/sr-設定` を案内する。

## config.sh に必要な変数（AI が書くときの目安）

- `CONFIGURED="true"` （必須）
- `DOMAIN_PATH`, `USECASE_PATH`, `INFRA_PATH`（例: `src/domain`, `src/useCase`, `src/infrastructure`）
- `TEST_DIR`（例: `tests`）, `SOURCE_EXTENSIONS`（例: `ts tsx js jsx`）, `TEST_EXTENSIONS`（例: `test.ts spec.ts`）
- `TDD_ENABLED`, `SPEC_RUNNER_DDD_ENABLED`（`"true"` / `"false"`）
- `BUILD_CMD`, `TEST_CMD`, `LINT_CMD`（例: `npm run build`, `npm test`, `npm run lint`）
- その他、既存の `.spec-runner/config.sh` にあれば同じ形式で揃える（`SPEC_RUNNER_FRAMEWORK`, `SPEC_RUNNER_TOOLS`, `SPEC_RUNNER_LANGUAGE`, `CI_PLATFORM` など）。

非対話で実行したいときは、上書き確認もスキップするため `SR_YES=1 ./.spec-runner/scripts/spec-runner.sh init <引数>` のように実行してよい。
