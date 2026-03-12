# 開発ルール（Claude Code 向け）

このプロジェクトは **scripts/spec-runner.sh** によるフェーズゲートで運用している。  
本ファイルは AI 向けの指示であり、**scripts/spec-runner.sh** はフェーズが通過していないと実行を拒否するため、設計をスキップできない。

---

## 最優先ルール

**何かを実装する前に必ず実行せよ：**

`./scripts/spec-runner.sh status`（チャットでは `/sr-状態`）で現在のフェーズを確認する。

`phase` が `implement` でない場合、実装コードを生成してはならない。
代わりに「現在のフェーズを確認してください」と伝えてユーザーに委ねよ。

---

## TDD（テスト駆動）ルール（デフォルトで有効）

**実装フェーズに進むまでに、テストを必ず含める。**

1. **テスト設計** … `docs/04_テスト設計/<UC名>.md` を書く
2. **テストを先に書く（Red）** … 実装より前にテストコードを書き、失敗することを確認する
3. **テストコードをコミット** … `./scripts/spec-runner.sh set-gate test_code_committed` でゲート通過
4. **実装で Green** … `implement` フェーズでテストを通す実装を書く

ドキュメントだけでなく**テストコードも必須**。テストを書かずに実装に進むことはできない。ゲートが `TEST_DIR` 配下の未コミットを検出し、コミットするまで `implement` に進めない。

- **テストのパス**は `.spec-runner/config.sh` の `TEST_DIR` で動的に指定（例: `tests`, `spec`, `__tests__`）。ここに置いたテストが未コミットだと implement ゲートでブロックされる。
- TDD をオプションにしたい場合: `export TDD_ENABLED="false"` にすると、実装前にテストコードを書かなくても `implement` に進める。

---

## スラッシュコマンド（チャット用）

### .claude/commands/（Claude Code カスタムスラッシュコマンド）

`.claude/commands/` に Markdown を置くと、チャット欄で `/sr-憲章` や `/sr-状態` などのスラッシュコマンドとして呼び出せる。各ファイルは「spec-runner.sh を実行せよ」という指示になっており、**ハード強制**に繋がる。コマンド一覧は **README の「スラッシュコマンド」** を参照。各 .md 内の `$ARGUMENTS` には、ユーザーがスラッシュの後に続けて入力した文字列が入る。

### 自然言語・短いスラッシュでの依頼

ユーザーが `/init`・`/status`・`/design-high` などの短いスラッシュ、または「init して」「顧客登録で design-high まで進めて」などの自然言語で依頼した場合も、**必ず** 対応する `./scripts/spec-runner.sh` をターミナルで実行すること（上記の `/sr-*` と同じ動作）。

---

## フェーズ別の行動規則

### require（要件定義）フェーズ
- `docs/01_要件/<UC名>.md` を編集する
- 実装・設計・テーブル定義は書かない
- 完了後: `./scripts/spec-runner.sh review-pass docs/01_要件/<UC名>.md`

### design-high（概要設計）フェーズ
- `docs/02_概要設計/<UC名>.md` を編集する
- ユースケース記述とドメインモデル候補の洗い出しのみ
- **具体的なメソッド定義・テーブルカラムは書かない**
- 新しい概念が出たら先に `docs/03_用語集.md` に追加する
- 完了後: `./scripts/spec-runner.sh review-pass docs/02_概要設計/<UC名>.md`

### design-detail（詳細設計）フェーズ
この順序で作業する：

1. **domain** → `docs/03_詳細設計/<UC名>/ドメイン.md`
   - エンティティ・値オブジェクト・ドメインイベント・集約・リポジトリIF
   - 振る舞い（メソッド）の定義
   - ← レビュー通過後に次へ

2. **usecase** → `docs/03_詳細設計/<UC名>/ユースケース.md`
   - ドメインモデルを使う設計（ドメインモデルを参照して書く）
   - Command/Query の入出力・シーケンス図
   - ← レビュー通過後に次へ

3. **table** → `docs/03_詳細設計/<UC名>/テーブル.md`
   - ドメインモデル ≠ テーブル（用途で分けてOK）
   - ER図（Mermaid）
   - ← レビュー通過後に次へ

4. **infra** → `docs/03_詳細設計/<UC名>/インフラ.md`
   - APIエンドポイント定義
   - リポジトリ実装方針
   - フロントエンドコンポーネント構成
   - ← レビュー通過後に次へ

### test-design（テスト設計）フェーズ
- `docs/04_テスト設計/<UC名>.md` を編集する
- **TDD: テストコードを実装より先に書く（Red 状態で OK）**
- テストコードをコミットしてから次へ: `./scripts/spec-runner.sh set-gate test_code_committed`
- 完了後: `./scripts/spec-runner.sh review-pass docs/04_テスト設計/<UC名>.md`

### implement（実装）フェーズ
- **TDD: テストを Green にする実装を書く**
- 設計と乖離した場合は先にドキュメントを更新する
- コードとドキュメントを同一コミットに含める
- 完了後: `./scripts/spec-runner.sh complete`

---

## ドキュメント同時更新ルール

| 変更内容 | 必ず同時更新するもの |
|---------|-------------------|
| `Domain/` 配下のクラス変更 | `docs/03_詳細設計/<UC名>/ドメイン.md` |
| `UseCase/` 配下のクラス変更 | `docs/03_詳細設計/<UC名>/ユースケース.md` |
| `Infrastructure/Api/` の変更 | `docs/03_詳細設計/<UC名>/インフラ.md` |
| DBマイグレーション | `docs/03_詳細設計/<UC名>/テーブル.md` |
| 新しいエンティティ/値オブジェクト | `docs/03_用語集.md` |
| アーキテクチャ判断 | `docs/99_設計判断記録/<番号>-<タイトル>.md` |

---

## ユビキタス言語ルール

- 設計ドキュメント → `docs/03_用語集.md` の **日本語** 列を使う
- コード（クラス名・メソッド名・変数名）→ **英語** 列を使う
- PHPDoc/JSDoc → 日本語のユビキタス言語を `@description` に併記する
- 新しい概念が登場 → **まず `docs/03_用語集.md` に追加してから**設計・実装に入る

---

## DDDレイヤー依存ルール（違反禁止）

```
Infrastructure → UseCase → Domain
```

- `Domain/` のコードは `UseCase/` や `Infrastructure/` を import してはならない
- `UseCase/` のコードは `Infrastructure/` の具体実装を import してはならない
- Eloquentモデルは `Infrastructure/Persistence/` のみで使用する

---

## Gitコミットメッセージ

```
<type>(<scope>): <日本語の説明>

type: feat, fix, docs, refactor, test, chore
scope: domain, usecase, infra, frontend, design, adr, test
```

