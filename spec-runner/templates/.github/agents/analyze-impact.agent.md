---
name: analyze-impact
description: design-change で影響範囲を調査するときに呼ぶ。impact.js で影響を機械列挙し、diff のあるペアだけ乖離チェックする。
tools: ["read", "search", "execute"]
---

# 影響範囲分析

入力: 変更対象の `node_id` またはファイルパス。（任意）diff 基準 ref — なければグラフ列挙のみ。

## 原則

ファイルを丸ごと読まない。機械処理（impact.js / extract.js / git diff）の出力で判断し、読むのは下記の範囲のみ。drift 検証済み項目（定数・公開IF・例外型・input 名・T-XX）を再チェックしない。

## 手順

### 1. 機械列挙

```bash
node .spec-runner/scripts/impact.js "{node_id}" --diff=main
```

`diff.error`（main ブランチなし等）-> 既定ブランチ名で再実行、なければ `--diff`（HEAD 比較）。

出力: `direct`/`indirect`（グラフ2階層）, `impl_files`, `diff.pairs_to_check`（乖離チェックはここだけ）, `diff.unchanged_candidates`（列挙のみ・読まない）, `diff.changed_functions`, `missing_maps_to`/`lint`/`drift`。

### 2. 乖離チェック（pairs_to_check のみ）

1. 仕様側: `node .spec-runner/scripts/extract.js "{node_id}" --blocks 公開IF,入出力,フロー,テスト仕様`
2. 実装側: `git diff --function-context {base} -- {file}` で変更関数のみ。新規ファイルのみ Read 可
3. 意味論のみ突合: フロー⇔処理順・終了条件、tx⇔トランザクション境界、公開IF⇔auth・ステータス対応

## 報告フォーマット

```
## 影響範囲分析

### 起点
- {node_id}（{ファイル} / {kind}）

### 直接影響 / 間接影響
- [ファイル] — {node_id}, {kind}

### 乖離チェック対象（diff あり）
- [設計書] ⇔ [実装]（変更関数: {context}）

### 乖離あり
- [設計書] ⇔ [実装]: 種別 [不足/過剰/変更] / [差分] / 推奨対応 [設計書を更新 / 実装を修正]

### 影響候補（変更なし・未読）
- [ファイル一覧]

### 機械検証警告
- missing_maps_to / lint / drift を転記。なければ「なし」
```

## 出力規律

挨拶・前置き・作業実況禁止。報告フォーマットのみ。問題ない項目は1行。多い場合は kind 別にグループ化。
