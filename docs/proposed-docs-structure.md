# docs/ フォルダ構造案

```
docs/
├── 01_要件定義/
│   ├── 要件定義.md                          # プロジェクトの目的・背景・解決する問題
│   └── ユビキタス言語辞書.md                # ドメイン用語の定義
│
├── 02_概要設計/
│   ├── システム全体俯瞰.md                  # コンポーネント全体図・境界・責務の概要
│   ├── ドメインモデル.md                    # 集約・境界コンテキスト図
│   ├── ユースケース一覧.md                  # UC一覧（番号・名前・概要・正常フロー）
│   └── 90_ADR/
│       └── mmdd-{対象}-{日本語タイトル}.md # 設計判断の記録。対象は ドメイン/UC/DB
│
└── 03_詳細設計/
    ├── 01_ドメイン/
    │   └── {ドメイン名}.md                 # 集約・値オブジェクト・ドメインルール
    ├── 02_ユースケース/
    │   └── UC-{日本語名}.md               # UC単位の詳細設計（ドメインをどう使うか）
    └── 03_DB・外部サービス/
        ├── スキーマ定義.dbml               # スキーマ定義（DBML形式）
        └── 外部サービス.md                 # 外部APIの接続仕様・認証方式
```

---

## node_id 体系

| 対象 | node_id 形式 | 例 |
|------|-------------|-----|
| 要件定義 | `requirement.{名前}` | `requirement.要件定義` |
| システム全体俯瞰 | `overview.system_context` | — |
| ドメインモデル | `overview.domain_model` | — |
| ユースケース一覧 | `overview.use_case_list` | — |
| ADR | `overview.adr.{slug}` | `overview.adr.0404-ドメイン-注文集約` |
| ドメイン詳細設計 | `detail.domain.{ドメイン名}` | `detail.domain.注文` |
| UC 詳細設計 | `detail.usecase.{UC名}` | `detail.usecase.注文確定` |
| DB・外部サービス | `detail.db.{名前}` | `detail.db.スキーマ定義` |

```yaml
---
spec_runner:
  node_id: detail.usecase.注文確定
  kind: detailed_design
  depends_on:
    - overview.use_case_list
    - detail.domain.注文
  maps_to:
    - src/application/order/confirm.py
    - src/domain/order/aggregate.py
    - tests/application/order/test_confirm.py
---
```

## maps_to 方針

- UC 単位の詳細設計は複数 src ファイルを列挙してよい（1:多 OK）
- `maps_to` は**必ず設定する**。空のままにしない
- design-reviewer / impact-analyzer は `maps_to` を唯一の参照先とする（パス推定しない）

## 廃止 UC の扱い

- ファイルを**削除する**（git 履歴で追う）
- 廃止理由は ADR に記録する（`overview.adr.mmdd-UC-{UC名}-廃止`）

---

## 各ファイルの役割メモ

### 03_詳細設計/01_ドメイン/{ドメイン名}.md
- 集約・値オブジェクト・エンティティの責務
- ドメインルール・制約
- コード・クラス定義は書かない

### 03_詳細設計/02_ユースケース/UC-{名前}.md
- ドメインをどう呼び出して何を実現するか
- 入出力・判断条件・エラーポリシー
- テスト観点
- `maps_to` で対応する src ファイルを列挙
- コード・プロンプト本文は書かない

### 03_詳細設計/03_DB・外部サービス/
- スキーマ・テーブル設計
- 外部APIの接続仕様・認証方式

---

## 検討ポイント（修正時に判断してください）

1. **概要設計のUCと詳細設計のUCは1:1にするか？**
   - 今は同じ粒度で対応させる案。概要で大きいUCを詳細で分割する可能性もある

2. **ドメインの粒度**
   - 1ファイル1ドメインか、サブドメインでさらに分けるか

