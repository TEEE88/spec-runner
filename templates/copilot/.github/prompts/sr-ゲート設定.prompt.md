---
agent: 'agent'
description: 'spec-runner: ゲート通過を記録'
argument-hint: 'ゲート名（例: glossary_checked, test_code_committed）'
tools: ['shell']
---

以下を**必ずシェルで実行**してください。

```bash
./.spec-runner/scripts/spec-runner.sh set-gate ${input:gate:ゲート名}
```

引数が空の場合は、ユーザーに「ゲート名を指定してください」と伝えてください。