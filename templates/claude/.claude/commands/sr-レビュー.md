# /sr-レビュー

**チャットで使うコマンド**。$ARGUMENTS にレビュー通過させるファイルパスを指定し、以下を**ターミナルで実行**してください（例: `/sr-レビュー docs/01_要件/顧客登録.md`）。

```bash
./.spec-runner/scripts/spec-runner.sh review-pass $ARGUMENTS
```

引数が空の場合は、ユーザーに「レビュー通過させるファイルパスを指定してください（例: docs/01_要件/顧客登録.md）」と伝えてください。
