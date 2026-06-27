---
name: design-change
description: 既存機能の変更を docs 正本で進めるフローガイド。影響特定、設計記録、設計修正、TDD 実装、検証を状態ファイル駆動で進める。
---

# design-change

ステップは順番どおり。承認は **Step 1 末・2 末・3 末の3回だけ**。それ以外で確認を挟まない。
設計記録テンプレート: `templates/02_概要設計/90_ADR/{mmdd}-{日本語タイトル}.md`

## 前提: architecture.yaml

開始前に `.spec-runner/architecture/architecture.yaml` を読む:

- `scope`（backend / frontend / all）-> フロントエンド設計書を対象に含めるか判断。**このスキルから scope 不一致のセクション（「scope: XX はスキップ」注釈）を削除して最適化する**
- `folder_structure` -> 影響ドキュメントのパス確認

設計変更で方針・構成が変わったら architecture.yaml も更新。

## 状態ファイル（全ステップの共有メモリ）

Step 1 で `.spec-runner/state/{mmdd}-{変更タイトル}.yaml` を作成。以降の全ステップ・委任で参照。同じ調査・説明を二度行わないための唯一の正本。

```yaml
target_node: 詳細.ユースケース.ページスクレイピング
impact:                # @analyze-impact 結果キャッシュ（実行は1回だけ）
  pairs_to_check: []
  candidates: []
decisions:             # 承認済み事項。再質問・再説明禁止
  - 最終ページ検出は URL 比較方式
checklist:
  - { file: docs/.../UC-ページスクレイピング.md, status: done }
  - { file: src/scraper/run.py, status: pending }
```

## Step 1: 変更整理と影響特定（承認1）

1. 背景・目的・制約の曖昧点を一問一答で深掘り（推奨回答を添える。コードで確認できることは質問しない）
2. 変更起点の docs / node_id を特定
3. `@analyze-impact` に委任。prompt に `node .spec-runner/scripts/impact.js "{node_id}" --diff=main` 起点を明記。**実行は1回だけ** -> 結果を状態ファイル `impact:` に保存
4. `scope: all` かつ UC の入出力・公開IF が変わる場合、フロント画面設計（`01_画面/` の API 連携）も対象に追加
5. 状態ファイル作成 -> チェックリスト提示 -> 承認

## Step 2: 設計記録（必要時のみ、承認2）

1. アーキテクチャ・責務境界・保存方式・外部 IF の意思決定が必要か判定。不要なら Step 3 へ
2. 3案提示（概要・メリット・デメリット・適合性）-> ユーザー決定
3. テンプレートから生成。決定を状態ファイル `decisions:` に追記 -> 承認

配置・命名は `.claude/rules/design-docs.md` の ADR テーブル。

## Step 3: 設計修正（承認3）

チェックリストの docs を上流 -> 下流に1パスで修正。完了ごとに `status` 更新。

- **3a. 概要設計**（変更ある場合のみ）: 「何をするか」に留める。バックエンド（scope: frontend はスキップ）-> フロントエンド（scope: backend はスキップ）-> API 変更時は `API仕様.md`
- **3b. 詳細設計**: ハイブリッド仕様YAML形式（design-docs.md）。テスト仕様の追加・変更もここで確定。`depends_on`/`maps_to`/`satisfies`（要件が増減した場合は要件定義の REQ も）更新。hooks の lint 警告はこの場で直す
- **3c. ベストプラクティス調査**（未知技術がある場合のみ）: URL を `.spec-runner/references/resources.md` に追記 -> WebSearch -> `docs/04_調査資料/{カテゴリ名}/{トピック名}.md`

全修正完了 -> 承認。

## Step 4: TDD 実装

`test-driven-development` スキルへ。仕様は extract.js 部分抽出で受け渡し。設計書の再確認・再説明禁止（Step 3 で確定済み）。

## Step 5: 検証

`@run-tests` と `@review` を**同時起動**。`@review` には node_id と「pairs_to_check のみ監査」を明記。両結果を確認 -> 問題あれば修正 -> checklist 全件 done。

**phase-gate**: `node .spec-runner/scripts/render.js` → `.spec-runner/scan/dashboard.md` を読み、以下を全て確認してから完了報告:
- drift: 0件
- unmapped: 0件

## Step 6: ハーネスエンジニアリング（繰り返し発生した問題がある場合のみ）

このサイクルで同じ補足説明・手戻り・ルール不足・責務の曖昧さが**繰り返し**発生した場合は `harness-engineering` で改善する。1回限りの例外は対象外。
