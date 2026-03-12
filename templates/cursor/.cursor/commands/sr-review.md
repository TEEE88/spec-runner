# /sr-review

以下を**必ずターミナルで実行**してください。ユーザーが続けて入力したファイルパスを渡します（例: `/sr-review docs/requirements/顧客登録.md`）。

```bash
./scripts/spec-runner.sh review-pass <ユーザーが入力したファイルパス>
```

引数が空の場合は、ユーザーに「レビュー通過させるファイルパスを指定してください」と伝えてください。
