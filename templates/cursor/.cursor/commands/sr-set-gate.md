# /sr-set-gate

**チャットで使うコマンド**。ユーザーが `/sr-set-gate` の後に続けて入力したゲート名で、以下を**ターミナルで実行**してください（例: `/sr-set-gate glossary_checked`）。

```bash
./scripts/spec-runner.sh set-gate <ユーザーが入力したゲート名>
```

引数が空の場合は、ユーザーに「ゲート名を指定してください（例: glossary_checked, test_code_committed）」と伝えてください。
