# /sr-set-gate

以下を**必ずターミナルで実行**してください。ユーザーが続けて入力したゲート名を渡します（例: `/sr-set-gate glossary_checked`）。

```bash
./scripts/spec-runner.sh set-gate <ユーザーが入力したゲート名>
```

引数が空の場合は、ユーザーに「ゲート名を指定してください（例: glossary_checked, test_code_committed）」と伝えてください。
