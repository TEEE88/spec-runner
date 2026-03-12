# /sr-design-detail

以下を**必ずターミナルで実行**してください。$ARGUMENTS にはサブフェーズ（domain / usecase / table / infra）のいずれかを指定します（例: `/sr-design-detail domain`）。

```bash
./scripts/spec-runner.sh design-detail $ARGUMENTS
```

引数が空、または domain / usecase / table / infra 以外の場合は、ユーザーに「サブフェーズを指定してください: domain, usecase, table, infra」と伝えてください。
