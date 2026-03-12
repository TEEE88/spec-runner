---
agent: 'agent'
description: 'spec-runner: 詳細設計サブフェーズ（domain / usecase / table / infra）'
argument-hint: 'domain | usecase | table | infra'
tools: ['shell']
---

以下を**必ずシェルで実行**してください。

```bash
./scripts/spec-runner.sh design-detail ${input:sub:サブフェーズ（domain, usecase, table, infra）}
```

引数が無効な場合は、ユーザーに「domain, usecase, table, infra のいずれかを指定してください」と伝えてください。
