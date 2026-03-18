# spec-runner の進め方（実装準拠）

このドキュメントは **リポジトリ内の実装**（`templates/.spec-runner/scripts/spec-runner-core.sh`、`steps/steps.json` 等）に沿って書いています。  
「次のステップ」は **1 本のコマンド**が返す **1 つの `command_file`（`.spec-runner/steps/*.md`）** だけです。

---

## 入口コマンド（毎回）

| 用途 | コマンド（プロジェクトルート） |
|------|-------------------------------|
| 次のステップ（人間向けテキスト） | `./.spec-runner/spec-runner.sh` または `./.spec-runner/spec-runner.sh 次のステップ` |
| 次のステップ（JSON） | `./.spec-runner/spec-runner.sh 次のステップ --json` |
| Lock 一覧 | `./.spec-runner/spec-runner.sh 次のステップ --lock`（内部では `--status`） |
| グレード判定ガイド | `./.spec-runner/spec-runner.sh 次のステップ --グレード` |

- **やること**: 出力の `command_file` を開き、その `.md` の指示どおりに作業する。
- **毎回の検証**: `steps.json` の `common.commands.check` → 既定は `.spec-runner/scripts/check.sh`。

### `--json` の主なフィールド（実装どおり）

| フィールド | 意味 |
|------------|------|
| `phase` | 数値（`steps.json` の各 step の `phase` と概ね対応） |
| `phase_name_ja` | 表示用ラベル（コアが付与） |
| `step_id` | `steps.json` の `id`（例: `charter`, `uc_spec`, `clarify`） |
| `command` | ステップの日本語名（`name_ja`） |
| `command_file` | 絶対パス想定の `.spec-runner/steps/<md_file>` |
| `grade` | `grade-history.json` の `current_grade` |
| `check_command` | 毎回のチェック用シェルコマンド |
| `step_commands` | そのステップ用のコマンド配列（JSON） |
| `feature_dir` / `feature_spec` | UC ブランチ時、該当 UC のディレクトリ・仕様書パス（取れれば） |

---

## 状態の単一ソース

### `.spec-runner/phase-locks.json`

実際のキーは次のとおり（各オブジェクトに `completed`, `locked_at`, `reviewed_by` 等）。

| キー | 意味 |
|------|------|
| `charter` | 憲章フェーズ完了。ゲートでは `reviewed_by` も参照（LOOP1 時） |
| `domain` | ドメイン設計フェーズ完了 |
| `architecture` | アーキ（実装計画）フェーズ完了 |
| `infra` | インフラ詳細（Grade A）完了 |
| `test_design` | テスト設計ロック（ゲート側で参照） |
| `uc_reviewed` | **文字列の配列**。UC 仕様ファイルの **ベース名（拡張子なし）** が入ると「レビュー通過」とみなす（例: `UC-1-foo`） |

### `.spec-runner/grade-history.json`

- `current_grade`: `LOOP1` / `A` / `B` / `C` など（**ブランチ名には含めない**）
- Grade A のとき、UC レビュー通過後は **インフラ詳細（`infra_plan`）** が先に出る（`infra.completed` が付くまで）

### `.spec-runner/project.json`

- `naming`: ブランチ接頭辞 `branch_prefix`（既定 `feature`）、`uc_id_pattern`、`other_work_prefixes`（例: `work`, `infra`, `cicd`）
- `required_docs`: ゲート確認時の必須パス（`steps:charter` 形式で `steps.json` の `common.docs` を参照）
- `test_design.dir` / `test_design.pattern`（既定: `tests`, `*.spec.*`）
- `test_design.require_uc_prefixed_tests`（既定: キー省略時 **true**）: **TDD 前提**。UC ブランチでは **`UC-N-` で始まり `pattern` に合致するテストファイル**が `test_design.dir` 内に無い限り **`test_design` のまま**（`implement` に進めない）。`false` にすると従来どおり「任意の spec が1つでもあれば実装」。
- `test_command.run`: **`require-tests-green.sh` が実行するテストコマンド**（実装完了の機械的条件）

---

## 「次のステップ」の分岐（`spec-runner-core.sh` の実際）

ブランチ種別・ロック・UC 有無・`uc_reviewed`・グレード・テストファイル有無で決まります。**紙の上の「常に UC→ドメイン→アーキ」の直線とは一致しません。**

### 1) UC ブランチ上（`feature/<UC-N>-<slug>` 形式）

1. 該当 `UC-N-*.md` が **まだ無い** → **`uc_spec`**（仕様策定）
2. 仕様はあるが **`uc_reviewed` にベース名が無い** → **`clarify`**（曖昧さ解消・レビュー通過まで）
3. レビュー済みかつ **Grade A かつ `infra.completed` でない** → **`infra_plan`**
4. それ以外で **当該 UC 用テストが未準備**（`require_uc_prefixed_tests` が true のときは **`UC-N-*.spec.*` 形式が1つ以上**）→ **`test_design`**
5. 上記を満たす → **`implement`**（あわせて **テストがグリーン**になるまで完了とみなさないのは `require-tests-green.sh` 側）

※ **ドメイン・アーキのロック未完了でも**、上記 UC ブランチ上では 3〜5 に進めます（コア実装どおり）。

### 2) UC ブランチではない（main 等）

実装では **次の順で最初に当てはまる分岐**が選ばれます（UC ブランチでも `other_work` ブランチでもない場合）。

1. **`charter.completed` でない** → **`charter`**
2. **ドメイン未ロックかつ `docs/02_...` に UC が 1 件以上** → **`domain`**
3. **ドメイン済みかつアーキ未ロック** → **`architecture_plan`**（`実装計画.md`）
4. **`other_work` 用ブランチ**（`feature/<other_work_prefix>/...`）かつ **2・3 を通過済み**（ドメイン完了＋アーキ完了、または UC 0 件で 2 をスキップした状態など）→ **`other_work`**  
   ※ **2** と同条件（UC あり・ドメイン未ロック）のときは **2 の `domain` が先**（`other_work` ブランチ上でも同様）。
5. **ドメイン未ロック**（この時点では UC が 0 件）→ **`uc_spec`**
6. **ドメイン・アーキともロック済み** → **`uc_spec`**（次の UC 開始）

要点:

- **初回**: main で UC がまだ無いと **5** で **`uc_spec`**。
- **UC がリポジトリに既にあるのにドメイン未ロック**（main で作業）→ **2** で **`domain`** が **`uc_spec` より先**。
- **アーキ**は **ドメイン完了後**に **3** で出る。

### 3) 自動では選ばれないステップ（`steps.json` にのみ存在）

次の `id` は **コアの `run_phase` では返しません**。各 `.md`（仕様策定・テスト設計等）の **手順の中で**使う想定です。

- `analyze`（分析）
- `checklist`（チェックリスト）
- `task_list`（タスク一覧）

---

## 成果物の置き場所（`steps.json` の `common.docs` と一致）

| キー | パス（既定） |
|------|----------------|
| 憲章 | `docs/01_憲章/憲章.md` |
| UC ルート | `docs/02_ユースケース仕様/<カテゴリ>/UC-N-<slug>.md` |
| ドメイン | `docs/03_ドメイン設計/`（ユビキタス言語辞書・ドメインモデル・集約 等） |
| アーキ | `docs/04_アーキテクチャ/` |
| インフラ | `docs/05_インフラ設計/`（例: `schema.dbml`） |
| API | `docs/06_API仕様/openapi.yaml` |

- UC ファイル名は **`UC-<N>-<slug>.md`**（`slug` は英数字・ハイフンが無難。ブランチ名も ASCII）。
- カテゴリフォルダ名は日本語可。

---

## ディレクトリ構成（パッケージテンプレに近い形）

```
<プロジェクトルート>/
├── .spec-runner/
│   ├── spec-runner.sh
│   ├── project.json              # 初回は project.json.example から
│   ├── phase-locks.json          # 初回は templates/phase-locks.json から
│   ├── grade-history.json
│   ├── scripts/
│   │   ├── spec-runner-core.sh
│   │   ├── check.sh              # --every / --full
│   │   ├── branch/uc-next-start.sh
│   │   └── test/require-tests-green.sh
│   ├── steps/                    # *.md + steps.json
│   ├── templates/                # 憲章・UC・ドメイン雛形等
│   └── hooks/                    # pre-commit / pre-push（任意）
├── docs/01_憲章/ … 06_API仕様/
├── tests/                        # project.json の test_design.dir
└── src/
```

- **`npx spec-runner`**: `.spec-runner/` を展開し、**`.claude/commands/spec-runner.md` を配置**（テンプレに存在する場合）。`.cursor/` への自動配置は **インストーラでは行っていない**。

---

## フェーズ番号とステップ（`steps.json`）

| phase | step_id（代表） | 内容 |
|-------|-----------------|------|
| 0 | `charter` | 憲章 |
| 1 | `uc_spec` / `clarify` / `other_work` | UC 仕様・曖昧さ解消・その他ブランチ |
| 2 | `domain` | ドメイン設計 |
| 3 | `architecture_plan` | 実装計画（アーキ） |
| 4 | `infra_plan` | インフラ詳細（Grade A） |
| 5 | `test_design` | PENDING テスト |
| 6 | `implement` | 実装・テストグリーン |

### 実装完了（Phase 6）の機械的条件

- **手動または CI で** `.spec-runner/scripts/test/require-tests-green.sh` が **exit 0** であること。
- 中身は `project.json` の **`test_command.run`** のみを `eval` 実行（例: `npm test`）。

### ゲート（`spec-runner-core.sh --gate`）のメモ

ゲートログ上の「Phase 1/2」表現は **ドメイン=Phase 1、アーキ=Phase 2** のように **steps.json の phase 番号と一致しません**。ロック対象は `phase-locks.json` のキーで判断してください。

---

## TDD が「どこまで」強制されるか

| レベル | 内容 |
|--------|------|
| **ゲート（次のステップ）** | 上記どおり **先に当該 UC の spec ファイルを置く**まで `implement` を出さない（`require_uc_prefixed_tests: true` 時）。 |
| **レッド→グリーンの順序** | **コミット順や「本番コードより先にアサーションを書いたか」は機械検査していない**。Phase 5 で PENDING/skip、Phase 6 で実装・グリーン、という **フェーズ順**での強制。 |
| **完了条件** | `require-tests-green.sh`（`test_command.run` 全通過）。 |

---

## 理想運用 vs コードのギャップ（把握用）

| 観点 | よく言われる理想 | 実コード |
|------|------------------|----------|
| UC とドメインの順序 | 常に UC 全部 → ドメイン | main 上では **UC が既にあるとドメインが先に出る** 分岐あり |
| UC 実装前にアーキ必須 | あり | **UC ブランチ上では**ドメイン・アーキ未ロックでもテスト設計・実装に進む |

運用で「必ずドメイン→アーキ→UC 実装」にしたい場合は、**ロックを先に済ませてから** UC ブランチに入る、またはコアの分岐変更が必要です。

---

## 日本語ドキュメント

`docs/` 配下の設計書は日本語で問題ありません。**Git 上はブランチ名・UC ファイルの slug は ASCII（kebab-case）推奨**です。
