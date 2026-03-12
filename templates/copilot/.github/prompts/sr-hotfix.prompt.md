---
agent: 'agent'
description: 'spec-runner: 緊急修正（負債として記録）'
argument-hint: '修正内容'
tools: ['shell']
---

以下を**必ずシェルで実行**してください。

```bash
./scripts/spec-runner.sh hotfix "${input:content:修正内容}"
```

引数が空の場合は、ユーザーに「修正内容を指定してください」と伝えてください。
