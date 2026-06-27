---
spec_runner:
  node_id: 概要.インターフェース.API仕様
  depends_on:
    - 概要.バックエンド.業務ロジック概要
    - 概要.フロントエンド.画面一覧
  maps_to:
    - docs/03_詳細設計/01_バックエンド/02_ユースケース/
    - docs/03_詳細設計/02_フロントエンド/01_画面/
---

# API仕様

```yaml
# パス⇔UC の目次。詳細なリクエスト・レスポンス仕様は各 UC / 画面ドキュメントが正本

エンドポイント:
  - path: "/api/{リソース}"
    method: GET
    概要: "{概要}"
    呼び出し元: "{画面名}"
  - path: "/api/{リソース}"
    method: POST
    概要: "{概要}"
    呼び出し元: "{画面名}"

認証:
  方式: "{JWT / Session / OAuth など}"
  トークン保持: "{Cookie / LocalStorage など}"
  認可: "{RBAC / ABAC など}"

スキーマ:
  フォーマット: "{JSON / Protocol Buffers など}"
  管理: "{OpenAPI / GraphQL Schema など}"
  バージョニング: "{URL バージョニング / ヘッダーなど}"
```
