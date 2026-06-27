---
spec_runner:
  node_id: 概要.インターフェース.外部API連携仕様
  depends_on:
    - 概要.システム俯瞰図
  maps_to:
    - docs/03_詳細設計/01_バックエンド/03_DB・外部サービス/
---

# 外部API連携仕様

```yaml
連携先:
  - サービス: "{サービス名}"
    用途: "{用途}"
    方向: "送信 / 受信"
    プロトコル: "{HTTP REST / gRPC / Webhook など}"
    ベースURL: "{ベース URL}"
    認証: "{API Key / OAuth など}"
    タイムアウト: "{秒数}"
    リトライ: "{回数}"
    フォールバック: "{方針}"
    主要API:
      - path: "{パス}"
        method: "GET / POST"
        概要: "{概要}"
```
