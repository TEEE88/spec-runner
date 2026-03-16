---
description: spec-runner（単一コマンド — spec-runner.sh 次のステップ でフェーズ判定し、.spec-runner/steps/ のステップ内容に従って進める）
---

> **このコマンドだけ使う。** スクリプトが現在フェーズを判定し、**ステップ内容**（`.spec-runner/steps/` 配下の .md）を返す。その内容に従えば、フェーズを手で管理せずに進められる。

## ユーザー入力

```text
$ARGUMENTS
```

入力がある場合は、必ずそれを考慮してから進める。

## 手順

1. **現在ステップを取得**  
   リポジトリルートから、常に `--json` を付けて実行する:
   ```bash
   .spec-runner/spec-runner.sh 次のステップ --json
   ```
   出力は JSON で、少なくとも以下を含む:
   - `phase` — 現在フェーズ（0〜6）
   - `phase_name_ja` — フェーズ名（日本語）
   - `command` — 推奨ステップ名（例: テスト設計）
   - `command_file` — そのステップの .md の絶対パス（`.spec-runner/steps/` 配下）
   - `grade` — 検出されたグレード（LOOP1 / A / B / C）

2. **ステップを読み実行する**  
   - `command_file` で示されたファイル（例: `.spec-runner/steps/テスト設計.md`）を開いて読む。
   - **そのファイルの指示を、この会話における現在ステップとして実行する。**

3. **結果を報告する**  
   - 実行したフェーズを簡潔に報告する。
   - 各ステップ末尾のとおり、**このコマンド（spec-runner）を再度実行**して次のステップに進む。

## ルール

- **spec-runner はこの 1 コマンドでよい。** 迷ったらこれを実行し、`command_file` の内容に従う。
- `spec-runner.sh 次のステップ` は lock ファイル・ブランチ・グレードからフェーズを判定する。lock がまだ無ければ Phase 0（憲章）から始める。
- ステップ内容は `.spec-runner/steps/` 配下にあり、spec-runner は現在フェーズ用のファイルを読み実行する。

