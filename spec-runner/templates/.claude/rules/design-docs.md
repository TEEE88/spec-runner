---
description: 設計書共通ルール（ヘッダー・命名規則・ADR・文書品質）
paths: ["docs/**"]
---

# 設計書共通ルール

## フェーズ管理

- ユーザー承認なしにフェーズを進めない
- フェーズは必ず `要件定義 -> 概要設計 -> 詳細設計 -> TDD -> 実装` の順に進める

## テンプレート

- 設計書は必ずテンプレートをコピーして生成する。独自にゼロから作成しない
- 手順: テンプレートを読む → 出力先へコピーする → プレースホルダーを埋める

## ヘッダー

- `docs/**` の全設計書にヘッダーを付ける
- 正本の必須項目は `spec_runner.node_id` / `spec_runner.kind` / `spec_runner.depends_on` / `spec_runner.maps_to`
- `depends_on` はまず文字列配列でよい。依存理由が必要な場合のみオブジェクト形式を使う
- `maps_to` には `src/` / `tests/` / IaC / 設定ファイルを列挙する。必ず設定する（空にしない）
- ADR は `node_id` と `kind` のみ。`depends_on` / `maps_to` は不要（決定の記録であり実装トレーサビリティに乗らない）
- `modules` / `source_files` などの拡張項目を足す場合でも、`maps_to` と矛盾させない

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

### node_id 体系

| 対象 | node_id 形式 | 例 |
|------|-------------|-----|
| 要件定義 | `requirement.{名前}` | `requirement.要件定義` |
| システム全体俯瞰 | `overview.system_context` | — |
| ドメインモデル（style: ddd のみ） | `overview.domain_model` | — |
| ユースケース一覧 | `overview.use_case_list` | — |
| ADR | `overview.adr.{slug}` | `overview.adr.0404-ドメイン-注文集約` |
| ドメイン詳細設計（style: ddd のみ） | `detail.domain.{ドメイン名}` | `detail.domain.注文` |
| UC 詳細設計 | `detail.usecase.{UC名}` | `detail.usecase.注文確定` |
| DB・外部サービス | `detail.db.{名前}` | `detail.db.スキーマ定義` |

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| `docs/01_要件定義` | 日本語 | `要件定義.md`, `ユビキタス言語辞書.md` |
| `docs/02_概要設計` | 日本語 | `ユースケース一覧.md`, `システム全体俯瞰.md` |
| `docs/02_概要設計`（style: ddd のみ） | 日本語 | `ドメインモデル.md` |
| `docs/02_概要設計/90_ADR/{対象}/` | `mmdd-{日本語タイトル}.md` | `0404-注文集約の設計.md` |
| `{対象}` の選択肢 | `全体` / `ドメイン` / `UC` / `DB` | — |
| `docs/03_詳細設計/01_ドメイン`（style: ddd のみ） | 日本語 | `注文.md`, `在庫.md` |
| `docs/03_詳細設計/02_ユースケース`（style: ddd） / `01_ユースケース`（style: layered） | `UC-{日本語名}.md` | `UC-注文確定.md` |
| `docs/03_詳細設計/03_DB・外部サービス`（style: ddd） / `02_DB・外部サービス`（style: layered） | 日本語 | `スキーマ定義.dbml`, `外部サービス.md` |

## ADR

- ADR は提案時に必ず 3 案を比較してから採用案を決める。ドキュメントには採用案と採用理由のみ記録する
- ADR は `docs/02_概要設計/90_ADR/{対象}/` で管理する（`全体` / `ドメイン` / `UC` / `DB`）
- ファイル名は `mmdd-{日本語タイトル}.md`。対象はフォルダで表す
- ADR は理由の記録であり、詳細設計の代わりにしない
- 廃止 UC の理由も ADR に記録する（UC ファイル本体は削除）

## 文書品質

- docs にコードを書かない（コード片・DDL・クラス定義・プロンプト本文）。コードは `src/` / `tests/` に書く
- 概要設計では「何をするか」を書く。実装の詳細は持ち込まない
- 詳細設計ではドメインルール・UC の責務・入出力・判断条件・テスト観点を書く
- `maps_to` を唯一の src 対応として使う。パス推定に頼らない
- Markdown に HTML タグ（details, summary, br など）を使わない
- 設計書に絵文字・記号（✓ ✅ ☑ ◯ × △ など）を使わない。状態・判定は文字で表現する
- `概要.md` のような汎用的な名前は使わない（`要件定義.md`、`ユースケース一覧.md` のように内容を示す名前にする）
- 「関連ドキュメント」セクションを設計書に作らない。依存関係はヘッダーの `depends_on` で管理する
- 「スケジュール」セクションを設計書に作らない。進捗管理は設計書の責務ではない

## ドメインモデルとデータモデルの分離（style: ddd のみ）

ドメインモデルとデータモデルは別物であり、置き場所も内容も分ける。

| 種別 | 内容 | 置き場所 |
|------|------|---------|
| ドメインモデル | ビジネスルール・集約・値オブジェクト・不変条件 | `docs/03_詳細設計/01_ドメイン/` |
| データモデル | DBスキーマ・テーブル定義・カラム定義・インデックス | `docs/03_詳細設計/03_DB・外部サービス/` |

- `01_ドメイン/` に DB スキーマ・テーブル定義・カラム定義を書かない
- `03_DB・外部サービス/` にビジネスルール・ドメインロジックを書かない
- 概要設計の `ドメインモデル.md` も同様。集約と境界コンテキストの概念図であり、永続化の構造ではない
