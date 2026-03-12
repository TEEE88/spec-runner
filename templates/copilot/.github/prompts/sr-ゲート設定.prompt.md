---
agent: 'agent'
description: 'spec-runner: ゲート通過を記録'
argument-hint: 'ゲート名（例: 用語集確認済み、テストコードコミット済み）'
tools: ['shell']
---

以下を**必ずシェルで実行**してください。

```bash
./.spec-runner/scripts/spec-runner.sh set-gate ${input:gate:ゲート名}
```

ゲート名は日本語（用語集確認済み、テストコードコミット済み など）または英語キーで指定できます。引数が空の場合は、ユーザーに「ゲート名を指定してください。例: 用語集確認済み、テストコードコミット済み」と伝えてください。