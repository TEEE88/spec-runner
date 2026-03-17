# spec-runner の進め方（全体像）

spec-runner は「いま何を作るべきか」を **`.spec-runner/spec-runner.sh 次のステップ --json`** で 1 つだけ返し、そのステップ（`.spec-runner/steps/*.md`）に従って設計→実装までを進める仕組みです。

このドキュメントは、**超具体の書き方ではなく**「どんな成果物を、どんな順で、どんな判断で作っていくか」を俯瞰します。

---

## まずやること（毎回共通）

- **入口コマンド**: プロジェクトルートで `./.spec-runner/spec-runner.sh 次のステップ --json`
- **やること**: 出力 `command_file`（`.spec-runner/steps/*.md`）を開き、その指示どおりに作業する
- **次へ**: 作業が終わったら同じコマンドをもう一度実行し、次のステップに進む

---

## 管理される “状態” と “判断材料”

- **フェーズの通過状態**: `.spec-runner/phase-locks.json`
  - 例: `charter.completed`, `domain.completed`, `architecture.completed` など
  - **レビュー“通過”の管理**はドキュメント本文に `status: reviewed` を書かず、**lock ファイルが単一ソース**になります（例: `charter.reviewed_by`, `domain.completed`, `uc_reviewed`）
- **グレード**: `.spec-runner/grade-history.json`（`LOOP1 / A / B / C`）
  - インフラ設計が必要な案件（Grade A）などで分岐します
- **ブランチ**: UC 作業は基本 `feature/UC-NNN-xxx`（接頭辞は `project.json` で変更可）

---

## 成果物の置き場所（基本ルール）

- **設計書は `docs/` 配下に集約**（プロジェクトルート直下）。**`docs/01..06`** とは次の 6 フォルダの総称です。

| 番号 | フォルダ名 | 内容 |
|------|------------|------|
| **01** | `docs/01_憲章/` | プロジェクト憲章（`憲章.md`）。原則・スコープ・非交渉事項・技術方針。Phase 0。 |
| **02** | `docs/02_ユースケース仕様/` | UC 仕様書（`<カテゴリ>/UC-NNN-xxx.md`）。1 UC = 1 ファイル。ユースケースからドメインを引き出すため最初に作る。 |
| **03** | `docs/03_ドメイン設計/` | ユビキタス言語辞書・ドメインモデル・集約など。UC を踏まえて固める。 |
| **04** | `docs/04_アーキテクチャ/` | パターン選定・インフラ方針・命名規則・設計判断記録（ADR）。Phase 2。 |
| **05** | `docs/05_インフラ設計/` | インフラ詳細（例: `schema.dbml`）。Grade A 時。Phase 4。 |
| **06** | `docs/06_API仕様/` | API の単一ソース（`openapi.yaml`）。API 公開時のみ。 |

- **注意**: 憲章の次は **UC（02）→ ドメイン（03）→ アーキ（04）** の順で進めます。
- **ユースケース（UC）仕様書は 1 UC = 1 ファイル**
  - `docs/02_ユースケース仕様/<カテゴリ>/UC-NNN-xxx.md`
  - 「実装方針」「タスク」も **UC 仕様書の末尾**に集約します
- **テストは `project.json` の `test_design.dir`（既定 `tests`）へ**
- **アプリケーションコードは `src/` 配下**（`docs/` と分離）

---

## 出来上がるフォルダ構造（一例）

フローに沿って進めた場合の、プロジェクトルート直下の想定構造です。

```
<プロジェクトルート>/
├── .spec-runner/                    # npx spec-runner で導入
│   ├── spec-runner.sh               # 入口（次のステップ --json）
│   ├── project.json                 # 設定（ブランチ命名・必須ドキュメント・テストコマンド等）
│   ├── phase-locks.json             # フェーズの通過状態
│   ├── grade-history.json           # グレード（LOOP1 / A / B / C）
│   ├── scripts/                     # spec-runner-core.sh, check, branch, test 等
│   ├── steps/                       # 憲章・ドメイン設計・仕様策定・曖昧さ解消・テスト設計・実装 等の .md
│   └── templates/                   # UC 仕様書ひな形（UC-NNN-ユースケース名.md）
├── docs/
│   ├── 01_憲章/
│   │   └── 憲章.md
│   ├── 02_ユースケース仕様/
│   │   └── <カテゴリ>/              # 例: 認証/, タスク管理/
│   │       ├── UC-NNN-xxx.md        # 例: UC-001-order-placement.md
│   │       └── ADR/                 # UC ごとの設計判断記録（任意）
│   │           └── UC-NNN-xxx/       # 例: UC-001-order-placement/
│   │               └── MMDD-題名.md  # 例: 0317-要件解釈の決定.md
│   ├── 03_ドメイン設計/
│   │   ├── ユビキタス言語辞書.md
│   │   ├── ドメインモデル.md
│   │   └── 集約.md
│   ├── 04_アーキテクチャ/
│   │   ├── パターン選定.md
│   │   ├── インフラ方針.md
│   │   ├── 命名規則.md              # 任意
│   │   └── 設計判断記録/            # ADR（MMDD-題名.md）
│   ├── 05_インフラ設計/             # Grade A の場合
│   │   └── schema.dbml             # 等
│   └── 06_API仕様/                  # API 公開時
│       └── openapi.yaml
├── tests/                           # project.json の test_design.dir（既定）
│   ├── unit/
│   │   └── UC-NNN-xxx.spec.*
│   └── e2e/
│       └── UC-NNN-xxx.e2e.spec.*
├── src/                             # アプリケーションコード（domain / app / infrastructure 等）
└── .claude/ or .cursor/             # コマンド定義（npx spec-runner で配置）
```

- カテゴリ名は日本語可（例: `認証`、`タスク管理`）。
- UC に閉じた判断理由は `docs/02_ユースケース仕様/<カテゴリ>/ADR/UC-NNN-xxx/` に ADR として残せる（任意）。横断の判断は `docs/04_アーキテクチャ/設計判断記録/`。
- `docs/05_インフラ設計/` と `docs/06_API仕様/` は、グレードや API 方針に応じて省略可。

---

## フェーズ概要（何を作るか）

### Phase 0: 憲章（Charter）

- **作るもの**: `docs/01_憲章/憲章.md`
- **狙い**: 原則・スコープ・非交渉事項・技術方針などを、後続の設計判断の “根拠” にする
- **通過**: 人間レビュー後に `phase-locks.json` 側で完了管理

### Phase 1: ユースケース仕様（UC）

- **作るもの**: `docs/02_ユースケース仕様/`
  - 例: `<カテゴリ>/UC-NNN-xxx.md`
- **狙い**: シナリオ（受入条件・フロー・例外）を先に書き、後続のドメイン設計の入力にする

### Phase 2: ドメイン設計（Domain）

- **作るもの**: `docs/03_ドメイン設計/`
  - 例: `ユビキタス言語辞書.md`, `ドメインモデル.md`, `集約.md`
- **狙い**: UC から用語・境界・集約を抽出して固め、共通の土台を作る
- **通過**: 人間レビュー後に lock を更新

### Phase 3: アーキテクチャ（Architecture）

- **作るもの**: `docs/04_アーキテクチャ/`
  - 例: `パターン選定.md`, `インフラ方針.md`, `設計判断記録/`（ADR）
- **狙い**: 実装に入る前に、重要な技術選択と判断基準を固定する
- **補足**: API を公開する場合は `docs/06_API仕様/openapi.yaml` を単一ソースとして扱う流れがあります

### Phase 4: インフラ詳細設計（Infrastructure, Grade A の場合）

- **作るもの**: `docs/05_インフラ設計/`（例: `schema.dbml` など）
- **狙い**: 変更が大きい案件で、DB/クラウド/ネットワーク等を実装前に確定する

### Phase 5: テスト設計（Test Design）

- **作るもの**: PENDING（未実装前提）のテストコード
  - 例: `tests/unit/UC-NNN-xxx.spec.*`, `tests/e2e/UC-NNN-xxx.e2e.spec.*`
- **狙い**: “完了の定義” を先に固定し、実装フェーズでグリーンにする

### Phase 6: 実装（Implementation）

- **やること**: Phase 5 の PENDING テストをグリーンにし、起動確認まで通す
- **必須**: `.spec-runner/scripts/test/require-tests-green.sh` が成功（exit 0）すること

---

## 日本語ドキュメント運用について

- `docs/` 配下の設計書（憲章・ドメイン・アーキテクチャ・UC 仕様など）は **日本語で問題ありません**
- ただし Git の都合で **ブランチ名や UC 仕様ファイル名は ASCII（kebab-case）** を基本にします
  - 日本語しか入力できない場合でも、ブランチ作成スクリプトがフォールバックして作成できるようになっています

