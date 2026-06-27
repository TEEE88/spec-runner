---
spec_runner:
  node_id: 詳細.ユースケース.{UC名}
  depends_on:
    - 概要.バックエンド.業務ロジック概要
    - 詳細.ドメイン.{ドメイン名}
    - 詳細.共通.エラーポリシー
  maps_to:
    - src/application/{uc_name}/
    - tests/application/{uc_name}/
---

```yaml
概要:
  title: UC-{UC名}
  purpose: {このUCの目的を1文。手順は書かない}
  satisfies: [REQ-{XX}]

定数:
  {定数名}: {値}   # {なぜこの値か}

公開IF:
  protocol: {REST / GraphQL / CLI / イベント}
  method: {GET / POST / PUT / DELETE}
  path: /api/{path}
  auth: {不要 / 必須(ロール)}
  成功: {200 / 201 / 204}
  エラー:
    - exceptions.{発生条件} -> {ステータスコード}  # ステータスコードは 詳細.共通.エラーポリシー に従う

入出力:
  inputs:
    - name: {入力名}
      type: {整数 / 数値 / 文字列 / 真偽 / 日時 / パス / 列挙(a|b)}
      default: {省略可}
      rule: {バリデーション制約。なければ省略}
      desc: {説明}
  outputs:
    - name: {出力名}
      dest: {保存先・返却形（該当する場合）}
      desc: {説明}
  exceptions:
    - type: {例外型}
      cond: {発生条件。1原因1エントリ}

フロー:
  - step: 1
    do: {1動作。定数は名前で参照する}
    error: {発生条件} -> {例外型}
  - step: 2
    tx: {原子性が必要な理由}
    body:
      - do: {同一トランザクション内の動作}
      - do: {同一トランザクション内の動作}
  - step: 3
    loop: {繰り返し対象（回数上限は定数名で）}
    body:
      - do: {ループ内の動作}
    exit: {終了条件}

非機能:
  冪等性: {再実行安全か。例: 同一リクエストIDは1回だけ処理}
  性能: {実装を変える予算のみ。例: 一覧取得は N+1 禁止・ページング必須}

テスト仕様:
  - id: T-01
    type: {単体 / 結合 / E2E}
    case: {条件と期待結果を1文}
  - id: T-02
    type: {単体 / 結合 / E2E}
    case: {例外時に 公開IF のステータスが返るケース}
    covers: [exceptions.{発生条件}]
```
