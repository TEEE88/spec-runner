# /sr-review

**チャットで使うコマンド**。ユーザーが `/sr-review` の後に続けて入力したファイルパスで、以下を**ターミナルで実行**してください（例: `/sr-review docs/requirements/顧客登録.md`）。

```bash
./scripts/spec-runner.sh review-pass <ユーザーが入力したファイルパス>
```

引数が空の場合は、ユーザーに「レビュー通過させるファイルパスを指定してください」と伝えてください。
