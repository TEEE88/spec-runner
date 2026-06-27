---
name: harness-engineering
description: skills・rules・agents・テンプレートを改善・保守するメタスキル。手戻り・ルール不足・責務の曖昧さ・テンプレート重複が繰り返し発生したときに使う。通常の機能実装や TDD には使わない。
---

# harness-engineering

## 使うタイミング

- 同じ補足説明・修正が繰り返し必要になった
- 複数の skill / rule / agent の責務が曖昧で手戻り・重複が発生
- skill / rule / agent の不足が品質・速度を継続的に落としている
- ユーザーがハーネス自体の改善を要求
- 別プロジェクトからの移植直後・大規模リネーム後の固有化と重複排除

使わない: 1回限りの例外対応 / 通常の実装・バグ修正 / アプリコードの TDD / 言い回しの微調整。

## Phase 1: 問題の抽出

何が詰まり、どこに無駄が出たか整理 -> 一時的か構造的（再発する）か判定 -> 改善対象を特定（skill / rule / agent / template）。
出力: 問題の要約・再発条件・変更対象候補。

## Phase 2: 対応方針の決定

1. 最小変更で解決できる対象を選ぶ。まず既存資産を直す。新 skill は「繰り返し使う独立ワークフロー」がある場合だけ
2. Claude / Copilot 両テンプレートへの影響を確認

## Phase 3: 修正

修正前に `.github/skills/harness-engineering/references/harness-format.md` を読む。

1. 意図が変わらない最小差分で修正（責務重複を増やさない。主要フローを壊さない。承認前提のフローを短絡しない）
2. **`.github/` のみ編集する**
3. スクリプト変更時は `node .spec-runner/scripts/scan.js` でエラーがないことを確認
4. references / templates は必要な範囲だけ更新

## Phase 4: 反映確認

`harness-format.md` の「プロジェクト固有化チェック」「重複排除チェック」を当てる。加えて:

- 変更が問題の原因に直接効いているか
- 関連 skill / rule / agent / template に矛盾・反映漏れがないか
- 今回限りのノイズをルール化していないか
- skill 名・起動条件を変えたら CLAUDE.md と一致しているか
- CLAUDE.md の肥大化（20行超 -> rules / skills へ移動を検討）
- docs 構造・命名・node_id に影響するなら design-docs.instructions.md と整合しているか
