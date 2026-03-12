---
agent: 'agent'
description: 'spec-runner: 詳細設定の対話のみ（パス・TDD等）。ユースケースは作らない'
tools: ['shell']
---

以下を**必ずシェルで実行**してください。

```bash
./.spec-runner/scripts/spec-runner.sh init
```

引数なしのため、対話でパス・TDD 等を聞かれたあと終了します。ユースケースを作成する場合は /sr-初期化 でユースケース名・集約名を指定してください。