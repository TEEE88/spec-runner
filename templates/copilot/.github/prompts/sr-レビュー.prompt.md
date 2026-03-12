---
agent: 'agent'
description: 'spec-runner: レビュー通過を記録'
argument-hint: 'ファイルパス（例: docs/01_要件/顧客登録.md）'
tools: ['shell']
---

以下を**必ずシェルで実行**してください。

```bash
./scripts/spec-runner.sh review-pass ${input:path:レビュー通過させるファイルパス}
```

引数が空の場合は、ユーザーに「ファイルパスを指定してください」と伝えてください。