# /sr-review

**チャットで使うコマンド**。$ARGUMENTS にレビュー通過させるファイルパスを指定し、以下を**ターミナルで実行**してください（例: `/sr-review docs/requirements/顧客登録.md`）。

```bash
./scripts/spec-runner.sh review-pass $ARGUMENTS
```

引数が空の場合は、ユーザーに「レビュー通過させるファイルパスを指定してください（例: docs/requirements/顧客登録.md）」と伝えてください。
