---
name: architecture-definition
description: 新規プロジェクトで docs と `.spec-runner/architecture/architecture.yaml` を立ち上げるための初期化フロー。
---

# architecture-definition

## 全体フロー

```
Phase 1: 要件整理
Phase 2: フォルダ構造の決定（対話）
Phase 3: アーキテクチャ判断の明文化
Phase 4: architecture contract 作成
Phase 5: architecture-skill-development へ自動移行
  └→ スキル整備完了後、プロジェクト専用スキルで概要設計へ進む
```

## Phase 1: 要件整理

1. 背景・提供価値・制約・スコープ外について、曖昧な点があれば一問一答で深掘りする（各質問に推奨回答を添える。コードで確認できることは質問しない）
2. ユーザーから背景、提供価値、制約、スコープ外を確認する
3. 作成スコープを確認する

   | scope | 選ぶ基準 |
   |-------|---------|
   | `all` | バックエンド・フロントエンドを両方作成する |
   | `backend` | バックエンドのみ作成する |
   | `frontend` | フロントエンドのみ作成する |

4. バックエンドのアーキテクチャスタイルを確認する（`scope: frontend` の場合はスキップ）

   このシステムは DDD スタイル（ドメイン → UC → DB・外部サービスの順）で設計する。

5. テンプレートをコピーして要件定義を作る

   - `docs/01_要件定義/要件定義.md`（テンプレート: `.github/skills/fullstack-seed/templates/01_要件定義/要件定義.md`）
   - `scope: all` または `scope: backend` の場合は `docs/01_要件定義/ユビキタス言語辞書.md` も作る（テンプレート: `.github/skills/fullstack-seed/templates/01_要件定義/ユビキタス言語辞書.md`）

6. 使用する AI 連携を確認する

   | 連携 | フォルダ |
   |------|---------|
   | `claude` | `.claude/`（Claude Code） |
   | `github` | `.github/`（GitHub Copilot） |
   | 両方 | `.claude/` と `.github/` |

7. ユーザーに確認・承認を得る

## Phase 2: フォルダ構造の決定

この段階で決めた構造がテンプレートの `maps_to` パスに焼き込まれるため、概要設計より前に確定させる。

1. 以下をユーザーと対話しながら決める
   - `src/` 配下のパッケージ・モジュール構成
   - `tests/` の種別ディレクトリ構成（`unit/` / `integration/` / `e2e/` など）
   - `docs/` の構成（デフォルトから変える場合）
   - その他プロジェクト固有のディレクトリ（IaC、設定ファイルなど）
2. 設計書とコードの責務が 1 対 1 で対応する単位をここで決める。1 つの主要責務を複数設計書へ分散させず、1 つの設計書に複数の主要責務を混ぜない
3. 決定した構造を箇条書きでまとめてユーザーに提示する
4. ユーザーに確認・承認を得る

## Phase 3: アーキテクチャ判断の明文化

1. ドメイン分割、責務境界、実装単位、インフラ方針を整理する
2. 必要なら対象フォルダに ADR を作る（`docs/02_概要設計/90_ADR/全体/` など）
3. ADR には比較案・採用理由・判断経緯を書く。設計書本文には採用後の仕様だけを書き、ADR の内容を再掲しない
4. ユーザーに確認・承認を得る

## Phase 4: architecture contract 作成

1. `.spec-runner/architecture/architecture.yaml` を作る（`.spec-runner/` は補助情報として扱う）
2. 最低限、以下を構造化する
   - integrations: Phase 1 で確認した連携（`[claude]` / `[github]` / `[claude, github]`）
   - scope: Phase 1 で確認したスコープ（`all` / `backend` / `frontend`）
   - style: `ddd`（固定）— `scope: frontend` の場合は省略可
   - folder_structure: Phase 2 で決定した構造（`src/` / `tests/` / `docs/` など）
   - domain_structure
   - runtime_units
   - design_policy
   - testing_policy
3. ユーザーに確認・承認を得る

## Phase 5: architecture-skill-development へ自動移行

Phase 4 が承認されたら、ユーザーにコマンドを打たせずに `architecture-skill-development` を続けて開始する。

1. `architecture-skill-development` に渡す前提（docs・architecture.yaml・確定済みフォルダ構造）を要約する
2. project 専用 skill に切り出すべき反復フローを列挙する
3. 確認なしに `architecture-skill-development` Phase 1 へ進む
4. スキル整備完了後、`fullstack-seed` で概要設計へ進む
