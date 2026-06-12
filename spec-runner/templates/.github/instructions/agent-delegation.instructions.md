---
applyTo: "**"
---

# サブエージェント委任ルール

メインは判断・対話・ファイル編集に集中。検証・調査・実行・検索はサブエージェントへ（メインのコンテキスト節約）。

## 委任先

| 場面 | 委任先 | タイミング |
|------|--------|-----------|
| 規約チェック・設計書⇔実装の整合確認 | `@review` | 実装・修正完了時 |
| テスト実行＋失敗分析 | `@run-tests` | 実装・修正完了時 |
| 影響範囲調査 | `@analyze-impact` | design-change の影響洗い出し時 |

独立して動けるエージェントは同時起動（例: 実装完了 -> `@run-tests` と `@review` を同時に）。

## メインが自分でやること

ユーザー対話・意思決定・承認受領 / フェーズ進行管理 / ファイル作成・編集 / サブエージェント結果の要点をユーザーへ伝達（生出力を貼らない）。

## 委任 prompt の必須事項

サブエージェントは CLAUDE.md / rules / skills を読まない。prompt に必ず含める:

1. 目的とゴール（冒頭1文）
2. 仕様は抽出ブロックで埋め込む: `node .spec-runner/scripts/extract.js "{node_id}" --blocks ...` の出力を `## 仕様` として埋め込む（ブロックは design-docs.instructions.md の抽出表）。フェンスなし設計書のみパスを渡す
3. 必読ルールファイル: `@review` コード規約 -> `.github/instructions/code-common.instructions.md` + `code-backend.instructions.md` or `code-frontend.instructions.md` / 設計整合 -> `design-docs.instructions.md` / テスト実行 -> `test-backend.instructions.md` or `test-frontend.instructions.md`
4. 範囲限定: 影響調査・整合レビューは `impact.js --diff` の `pairs_to_check` に限定
5. 報告フォーマットと文字数上限（例: 200語以内・箇条書きのみ）
6. 修正可否（レポートのみ / 修正可・ただし設計書を超えない）

design-change 進行中は状態ファイル（`.spec-runner/state/*.yaml`）のパスも渡し、`decisions:` の再質問を禁止する。

UC 新規実装の委任は仕様の `公開IF` ブロック必須。Router 配線は `公開IF` を正本として実装範囲（欠けると UC があっても 404）。
