---
name: harness-engineering
description: skills・rules・agents・テンプレートを改善・保守するメタスキル。手戻り・ルール不足・責務の曖昧さ・テンプレート重複が繰り返し発生したときに使う。通常の機能実装や TDD には使わない。
---

# harness-engineering

## 使うタイミング

以下のいずれかに当てはまるときに使う。

1. 同じ補足説明や修正が繰り返し必要になった
2. 複数の skill / rule / agent の責務が曖昧で、手戻りや重複が発生した
3. 既存の skill / rule / agent が不足しており、品質または作業速度を継続的に落としている
4. ユーザーが skill / rule / agent 自体の改善を求めた

## 使わないタイミング

- 1 回限りの例外対応
- 通常の機能実装やバグ修正
- アプリケーションコードに対する TDD
- 単なる言い回しの微調整で済む変更

## 全体フロー

```
Phase 1: 問題の抽出
Phase 2: 対応方針の決定
Phase 3: skill / rule / agent / template の修正
Phase 4: 影響範囲の反映確認
```

## Phase 1: 問題の抽出

1. 今回の作業で何が詰まり、どこに無駄が出たかを整理する
2. その問題が一時的なものか、再発しうる構造的な問題かを判定する
3. 改善対象を特定する（skill / rule / agent / template）

**出力:** 問題の要約・再発条件・変更対象の候補一覧

## Phase 2: 対応方針の決定

1. 最小変更で解決できる対象を選ぶ（まず既存の資産を直す。新しい skill は繰り返し使う独立したワークフローがある場合だけ追加する）
2. 新しい skill を増やすべきか、既存 skill / rule / agent の修正で十分かを判断する
3. Claude / Copilot の両テンプレートに影響するか確認する

## Phase 3: skill / rule / agent / template の修正

ファイルを作成・修正する前に `.claude/skills/harness-engineering/references/harness-format.md` を読み、フォーマットを確認する。

1. 対象ファイルを特定する
2. 意図が変わらない最小差分で修正する（役割の重複を増やさない。既存スキルの主要フローを壊さない。ユーザー承認が前提のフローは勝手に短絡しない）
3. `.claude/` と `.github/` を対で更新する
4. references や templates を参照している場合、必要な範囲だけ更新する

## Phase 4: 影響範囲の反映確認

- 問題の原因に対して、変更箇所が直接効いているか
- 関連する skill / rule / agent / template の記述が矛盾していないか
- Claude / Copilot の対応ファイルに反映漏れがないか
- 今回限りのノイズをルール化していないか
- skill 名・起動条件・使いどころを変更した場合、`CLAUDE.md` の記述と一致しているか
- `CLAUDE.md` が肥大化していないか（20行超えたら `rules/` や `skills/` へ移動を検討する）
- docs 構造・命名規則・node_id 体系に影響する変更の場合、`design-docs.md` と整合しているか
