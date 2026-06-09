---
applyTo: "backend/src/**,backend/tests/**"
---

# バックエンドコーディング規約

> このファイルはテンプレートです。`architecture-skill-development` で言語・フレームワーク・プロジェクト構造に合わせて書き換えてください。

共通ルール（コメント・テスト ID・後方互換）は `.github/instructions/code-common.instructions.md` 参照。

## プロジェクト固有の決定事項

> `architecture-skill-development` で以下をチームで合意し、`<...>` を書き換える。

- バックエンド言語: `<Python / Go / TypeScript / ...>`
- フレームワーク: `<FastAPI / Express / Django / ...>`
- ディレクトリ構造: `<レイヤードアーキテクチャ / DDD / Clean Architecture / ...>`

### コメント例

> プロジェクトの規約に合わせて書き換える。

```python
# ○ コメントは基本コードの上に書く
# Bedrock の一時的な 429 エラーに対応するためリトライ回数を設定
max_retries = 3

# ○ 短い定数の補足は行末でもよい
TIMEOUT_SEC = 30  # Bedrock の推奨値に合わせている

# ○ 処理ブロックのコメント（何）— 処理の概要を簡潔に書く
# 既存の会話履歴を取得してモデルに渡す形式へ変換する
messages = repository.find_by_conversation_id(conversation_id)
formatted = [to_llm_message(m) for m in messages]

# ○ 命名で分かることでもコメントを書く
# メッセージを永続化する
repository.save_message(message)

# ○ 関数の docstring — 短い場合は1行
def validate_attachments(files: list) -> None:
    """添付ファイル数の上限チェック。"""
    ...

# ○ 関数の docstring — 長い場合や入力・出力の説明がある場合は複数行
def _build_multimodal_content(text: str, file_data_map: dict) -> str | list:
    """
    テキスト + 添付ファイルを LangChain マルチモーダル content に変換する。

    入力:
        text: ユーザーの入力テキスト
        file_data_map: {attachment_id: (data_bytes, content_type)}
    出力:
        添付なし → str、添付あり → text/image_url パーツのリスト
    """
    ...

# × セクション区切りコメント
# ============ バリデーション ============  ← 禁止
```

## 言語・型固有ルール

> このセクションをフレームワーク・型システムに合わせて書き換える。

`<your-backend-language-and-type-rules>`

## 環境変数の整合性

env var を 1 件追加・変更したら同 PR で全部揃える。「ローカルで動いて本番で動かない」事故はこの欠落が原因。

揃えるべきファイル（プロジェクト構造に応じて調整）:
1. アプリケーション設定ファイル（環境変数を読み込む箇所）
2. インフラコード（CDK / Terraform 等）
3. docker-compose.yml（ローカル開発用）
4. 関連設計書

`os.environ.get("XXX", "fallback")` で偽値（`"local-bucket"` / `"test"` / `"dummy"` 等）を fallback に置く設計は禁止。production で偽値が黙って通る。

## バックグラウンドタスクの中断耐性

非同期タスクを fire-and-forget する設計では、デプロイやシャットダウンで中断される。中断されても回復できる設計を必須とする。

### 必須

- 一意キー（ID、external_id 等）をタスク起動前に確定させる
- 完了状態への遷移経路を 2 系統用意する
  1. background task 内での明示的な状態更新（成功時）
  2. 外形監視（ポーリング、cron、reconciler）が外部状態を見て自動修復

### 禁止

- 一意キーを background task 内で確定する設計
- 中間状態（処理中ステータス）が永遠に残ることを許容する前提

## 検索ルール

- コードの検索・置換は `backend/src/` と `backend/tests/` の両方を対象にする
