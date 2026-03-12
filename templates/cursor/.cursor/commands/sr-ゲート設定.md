# /sr-ゲート設定

**チャットで使うコマンド**。ユーザーが `/sr-ゲート設定` の後に続けて入力したゲート名で、以下を**ターミナルで実行**してください（例: `/sr-ゲート設定 glossary_checked`）。

```bash
./.spec-runner/scripts/spec-runner.sh set-gate <ユーザーが入力したゲート名>
```

引数が空の場合は、ユーザーに「ゲート名を指定してください（例: glossary_checked, test_code_committed）」と伝えてください。
