# /sr-set-gate

以下を**必ずターミナルで実行**してください。$ARGUMENTS にはゲート名を指定します（例: `/sr-set-gate glossary_checked`）。

```bash
./scripts/spec-runner.sh set-gate $ARGUMENTS
```

引数が空の場合は、ユーザーに「ゲート名を指定してください（例: glossary_checked, test_code_committed）」と伝えてください。
