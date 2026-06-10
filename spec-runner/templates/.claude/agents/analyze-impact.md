---
name: analyze-impact
description: design-change で影響範囲を調査するときに呼ぶ。node_id から連鎖する影響ファイルを一覧化し、maps_to の整合性を報告する。
tools: Bash
model: sonnet
---

# 影響範囲分析

## 入力

- 変更対象の `node_id`（例: `詳細.ユースケース.注文登録`）またはファイルパス

## 手順

### 1. graph.json の確認

`graph.json` は Edit / Write のたびに hooks で自動更新される。`.claude/.spec-runner/scan/graph.json` が存在しない場合のみ以下を実行する。

```bash
node .claude/.spec-runner/scripts/scan.js
```

### 2. 影響範囲をグラフから取得

```bash
node -e "
const g = require('./.claude/.spec-runner/scan/graph.json');
const id = '{node_id}';
const node = g.nodes[id] || {};
const direct = g.reverse_index[id] || [];
const indirect = [...new Set(
  direct.flatMap(n => g.reverse_index[n] || []).filter(n => !direct.includes(n) && n !== id)
)];
console.log(JSON.stringify({ node, direct: direct.map(n => ({id: n, ...g.nodes[n]})), indirect: indirect.map(n => ({id: n, ...g.nodes[n]})), missing: g.missing_maps_to }, null, 2));
"
```

### 3. 結果を一覧化する

### 4. 特定した設計書⇔実装ペアの乖離チェック

直接影響・間接影響のうち `maps_to` を持つノードについて、設計書と実装ファイルを対で読み、乖離を確認する。

1. `.claude/rules/design-docs.md` を読み、ヘッダー仕様と照合観点を把握する
2. 各ペアの設計書と `maps_to` 先の `src/` / `tests/` ファイルを読む
3. 責務・入出力・判断条件・テスト一覧が一致しているか確認する
4. 乖離があれば種別（不足 / 過剰 / 変更）と推奨対応をセットで報告する

## 報告フォーマット

```
## 影響範囲分析

### 起点
- node_id: {node_id}
- ファイル: {ファイルパス}
- kind: {kind}

### 直接影響（1階層目）
- [ファイルパス] — node_id: {node_id}, kind: {kind}

### 間接影響（2階層目）
- [ファイルパス] — node_id: {node_id}, kind: {kind}

### 実装影響（maps_to で対応）
- [src/ または tests/ のファイルパス]

### maps_to 整合性チェック
- OK: 全参照ファイルが存在する
- MISSING: {missing} — {source} ({node_id}) に記載されているが存在しない

### 設計書⇔実装 乖離チェック

#### 一致（問題なし）
- [設計書ファイル] ⇔ [実装ファイル]

#### 乖離あり
##### [設計書ファイル] ⇔ [実装ファイル]
- 種別: 不足 / 過剰 / 変更
- 内容: [具体的な差分の説明]
- 推奨対応: 設計書を更新 / 実装を修正

### 影響なし（確認済みで変更不要）
- [ファイルパス] — 理由: {理由}
```

影響ファイルが多い場合は kind 別にグループ化する。
