---
applyTo: "frontend/src/**,frontend/tests/**"
---

# フロントエンドコーディング規約

> テンプレート。`architecture-skill-development` で言語・フレームワーク・構造に合わせて書き換える。

共通ルール（コメント・テスト ID・準備/実行/検証マーカー・後方互換）は `.github/instructions/code-common.instructions.md`。

## プロジェクト固有の決定事項

- 言語: `<TypeScript / JavaScript / ...>`
- フレームワーク: `<Next.js / React / Vue / ...>`
- ディレクトリ構造: `<App Router / Pages Router / features 構成 / ...>`

### コメント例

```typescript
// フォームの入力値をAPI送信用のペイロードに整形する
const payload = buildPayload(formValues, selectedModel);

// 未読メッセージがある場合のみバッジを表示するためフィルタする
const unread = messages.filter((m) => !m.isRead);

/** 添付ファイル数の上限チェック */
function validateAttachments(files: File[]): void { ... }
```

長い JSDoc は入力・出力を複数行で書く。

## 言語・型固有ルール

`<your-frontend-language-and-type-rules>`

## テスト記述（フロントエンド固有）

- `test/it` 第一引数に ID とテスト名: `test("T-01: refresh=false時はクエリパラメータにrefreshを含まない", ...)`
- `// T-01: ...` の先頭コメント不要（第一引数と重複）

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

## 検索ルール

検索・置換は `frontend/src/` と `frontend/tests/` の両方を対象。
