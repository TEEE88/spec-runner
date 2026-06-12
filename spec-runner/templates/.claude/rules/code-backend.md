---
description: バックエンド固有規約。共通ルールは code-common.md を参照。
paths: ["backend/src/**", "backend/tests/**"]
---

# バックエンドコーディング規約

> テンプレート。`architecture-skill-development` で言語・フレームワーク・構造に合わせて書き換える。

共通ルール（コメント・テスト ID・後方互換）は `.claude/rules/code-common.md`。

## プロジェクト固有の決定事項

- 言語: `<Python / Go / TypeScript / ...>`
- フレームワーク: `<FastAPI / Express / Django / ...>`
- ディレクトリ構造: `<レイヤード / DDD / Clean Architecture / ...>`

### コメント例

```python
# Bedrock の一時的な 429 に対応するためリトライ回数を設定
max_retries = 3

TIMEOUT_SEC = 30  # Bedrock の推奨値

# 既存の会話履歴を取得しモデルに渡す形式へ変換する
messages = repository.find_by_conversation_id(conversation_id)

def validate_attachments(files: list) -> None:
    """添付ファイル数の上限チェック。"""
    ...
```

長い docstring は入力・出力を複数行で書く。セクション区切り（`# ==== ====`）禁止。

## 言語・型固有ルール

`<your-backend-language-and-type-rules>`

## 環境変数の整合性

env var を追加・変更したら同 PR で全部揃える（欠落 -> 「ローカルで動いて本番で動かない」）:

1. アプリ設定ファイル 2. インフラコード（CDK/Terraform） 3. docker-compose.yml 4. 関連設計書

`os.environ.get("XXX", "fallback")` の偽値 fallback（`"local-bucket"`/`"test"` 等）禁止。production で偽値が黙って通る。

## バックグラウンドタスクの中断耐性

fire-and-forget はデプロイ・シャットダウンで中断される。回復可能な設計を必須とする。

必須: 一意キーをタスク起動**前**に確定 / 完了状態への遷移経路を2系統（task 内の明示更新 + 外形監視による自動修復）
禁止: 一意キーを task 内で確定 / 中間状態が永遠に残る前提

## 検索ルール

検索・置換は `backend/src/` と `backend/tests/` の両方を対象。
