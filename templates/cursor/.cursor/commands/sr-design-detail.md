# /sr-design-detail

以下を**必ずターミナルで実行**してください。ユーザーが続けて入力したサブフェーズ（domain / usecase / table / infra）を渡します（例: `/sr-design-detail domain`）。

```bash
./scripts/spec-runner.sh design-detail <ユーザーが入力したサブフェーズ>
```

引数が空、または domain / usecase / table / infra 以外の場合は、ユーザーに「サブフェーズを指定してください: domain, usecase, table, infra」と伝えてください。
