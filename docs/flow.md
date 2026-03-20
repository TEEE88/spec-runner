# spec-runner フロー（シンプル版）

このドキュメントは、`templates/.spec-runner/scripts/spec-runner-core.sh` と `templates/.spec-runner/steps/steps.json` に合わせた最新フローを説明する。

## 入口コマンド

| 用途 | コマンド |
|---|---|
| 次のステップ | `./.spec-runner/spec-runner.sh 次のステップ --json` |
| lock 状態表示 | `./.spec-runner/spec-runner.sh 次のステップ --lock` |

## 設計方針

- `spec-runner` は **薄いオーケストレータ**（次の一手を返す）
- 正本は `docs/work.md`
- 主線は 6 ステップ（実行フェーズは5本 + 憲章）、横断は 2 ステップ
- ブランチ運用やグレード判定は強制しない

## 主線 6 ステップ

1. `charter`（憲章）
2. `uc_spec`（仕様策定）
3. `domain`（ドメイン設計）
4. `architecture_plan`（実装計画）
5. `test_design`（テスト設計）
6. `implement`（実装）

※ 運用上は「実行フェーズ5本（仕様→ドメイン→計画→テスト→実装）+ 憲章」で扱う。

## 横断 2 ステップ

- `clarify`（曖昧さ解消）
- `analyze`（分析）

これらは任意タイミングで使う補助ステップ。主線フェーズを増やさない。

## 次ステップ判定（概要）

`spec-runner-core.sh` は lock と成果物から次を返す。

1. `charter.completed` が false  
   - 憲章が未整備なら `charter`
   - 憲章があるなら `clarify` / `analyze` を先に返すことがある
2. `uc_discovery.completed` が false  
   - 未レビュー UC があれば `clarify` / `analyze`（UC 整合性チェック）
   - すべてレビュー済みなら `uc_spec`（次 UC 作成）
3. `domain.completed` が false  
   - 未レビュー UC が 1 件でも残っていれば先に `clarify` / `analyze`
   - 全 UC レビュー済みなら `domain`（必要に応じ `clarify` / `analyze`）
4. `architecture.completed` が false  
   - `architecture_plan`（必要に応じ `clarify` / `analyze`）
   - lock が true でも、設計成果物（`docs/03` / `docs/04` の `.md`）が無い場合は該当設計フェーズに戻る
5. 最新 UC がレビュー済みかつテスト準備済み  
   - `implement`  
   それ以外は `test_design`

## 正本（Single Source）

- フロー定義: `.spec-runner/steps/steps.json`
- 進行状態: `.spec-runner/phase-locks.json`
- 作業正本: `docs/work.md`
- 仕様本文: `docs/01..06`, `docs/02_ユースケース仕様/**`
- 実装検証: `tests/**`, `test_command.run`

## 運用ルール（最小）

1. 実装前に `docs/work.md` の受入条件を埋める
2. 作業中は `docs/work.md` のタスクを更新する
3. コミット前に `docs/work.md` の `- [ ]` を確認する
4. 完了時に `docs/work.md` の検証結果を更新する
5. UC を十分に作ってレビュー完了したら `uc_discovery.completed` を `true` にする
