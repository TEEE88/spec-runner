---
applyTo: "frontend/src/**,frontend/tests/**"
---

# フロントエンドコーディング規約

> このファイルはテンプレートです。`architecture-skill-development` で言語・フレームワーク・プロジェクト構造に合わせて書き換えてください。

共通ルール（コメント・テスト ID・後方互換）は `.github/instructions/code-common.instructions.md` 参照。

## プロジェクト固有の決定事項

> `architecture-skill-development` で以下をチームで合意し、`<...>` を書き換える。

- フロントエンド言語: `<TypeScript / JavaScript / ...>`
- フレームワーク: `<Next.js / React / Vue / ...>`
- ディレクトリ構造: `<App Router / Pages Router / features 構成 / ...>`

### コメント例

> プロジェクトの規約に合わせて書き換える。

```typescript
// ○ 処理ブロックのコメント（何）
// フォームの入力値をAPI送信用のペイロードに整形する
const payload = buildPayload(formValues, selectedModel);

// ○ コメントは基本コードの上に書く
// 未読メッセージがある場合のみバッジを表示するためフィルタする
const unread = messages.filter((m) => !m.isRead);

// ○ 命名で分かることでもコメントを書く
// モーダルを閉じる
closeModal();

// ○ 関数の JSDoc — 短い場合は1行
/** 添付ファイル数の上限チェック */
function validateAttachments(files: File[]): void {
  ...
}

// ○ 関数の JSDoc — 長い場合や入力・出力の説明がある場合は複数行
/**
 * フォームの入力値をAPI送信用のペイロードに整形する
 *
 * 入力:
 *   formValues: フォームの入力値
 *   selectedModel: 選択されたモデル名
 * 出力:
 *   API送信用のペイロードオブジェクト
 */
function buildPayload(formValues: FormValues, selectedModel: string): Payload {
  ...
}
```

## 言語・型固有ルール

> このセクションをフレームワーク・型システムに合わせて書き換える。

`<your-frontend-language-and-type-rules>`

## テスト記述規約

コーディング規約の一部として、テストコードの記述ルールもこのファイルで管理する。

### テスト命名・コメント規約

- ID とテスト名の記述: 全テストで設計書の `テスト一覧` と対応する `テストID` と `テスト名` を `test/it` の第一引数に含める（形式: `test("T-01: refresh=false時はクエリパラメータにrefreshを含まない", ...)`）
- 先頭コメント不要: `// T-01: ...` のようなテスト名コメントは書かない
- 準備・実行・検証: セットアップが 5 行以上のテストでは `// 準備 - ...` / `// 実行 - ...` / `// 検証 - ...` で構造を明示する。サフィックスには具体的に何をしているかを書く
- 英語コメント禁止: `Arrange` / `Act` / `Assert` 等の英語は使わない

```typescript
test("T-01: ある入力に対して期待する出力を返す", () => {
  // 準備 - テスト対象の入力データを用意する
  const input = ...;

  // 実行 - テスト対象の関数を呼び出す
  const result = targetFunction(input);

  // 検証 - 期待する出力と一致するか確認する
  expect(result).toBe(expectedOutput);
});
```

## 後方互換ハックの禁止

使われなくなったコードは完全に削除する。互換性維持のための温存は行わない。

禁止パターン:
- 使われない引数・変数を残す
- 削除した型・関数を再公開する
- `// removed`, `// deprecated`, `// 旧実装` コメントとともにコードを残す
- 後方互換用のラッパー関数・エイリアスを追加する

## 検索ルール

- コードの検索・置換は `frontend/src/` と `frontend/tests/` の両方を対象にする
