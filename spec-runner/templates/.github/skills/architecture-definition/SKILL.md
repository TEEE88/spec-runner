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

テンプレート: `.claude/skills/ddd-seed/templates/01_要件定義/`

1. 曖昧な前提があれば `spec-probe` スキルで先に整理する
2. ユーザーから背景、提供価値、制約、スコープ外を確認する
3. テンプレートをコピーして `docs/01_要件定義/要件定義.md` を作る
4. ドメイン用語が出てきたら `docs/01_要件定義/ユビキタス言語辞書.md` に随時追記する
5. アーキテクチャスタイルを選択する

   | スタイル | 選ぶ基準 |
   |---------|---------|
   | `ddd` | 複雑なビジネスドメインがある。集約・境界コンテキストで設計する必要がある |
   | `layered` | CRUD 中心またはビジネスロジックがシンプル。UC・サービス層で設計すれば十分 |

6. フロントエンドの有無を確認する

   | 値 | 基準 |
   |----|------|
   | `true` | Web UI・モバイル画面がある |
   | `false` | API・バックエンドのみ |

7. 使用する AI 連携を確認する

   | 連携 | フォルダ |
   |------|---------|
   | `claude` | `.claude/`（Claude Code） |
   | `github` | `.github/`（GitHub Copilot） |
   | 両方 | `.claude/` と `.github/` |

8. ユーザーに確認・承認を得る

## Phase 2: フォルダ構造の決定

この段階で決めた構造がテンプレートの `maps_to` パスに焼き込まれるため、概要設計より前に確定させる。

1. 以下をユーザーと対話しながら決める
   - `src/` 配下のパッケージ・モジュール構成
   - `tests/` の種別ディレクトリ構成（`unit/` / `integration/` / `e2e/` など）
   - `docs/` の構成（デフォルトから変える場合）
   - その他プロジェクト固有のディレクトリ（IaC、設定ファイルなど）
2. 決定した構造を箇条書きでまとめてユーザーに提示する
3. ユーザーに確認・承認を得る

## Phase 3: アーキテクチャ判断の明文化

1. ドメイン分割、責務境界、実装単位、インフラ方針を整理する
2. 必要なら対象フォルダに ADR を作る（`90_ADR/全体/` / `ドメイン/` / `UC/` / `DB/`）
3. ユーザーに確認・承認を得る

## Phase 4: architecture contract 作成

1. `.spec-runner/architecture/architecture.yaml` を作る（`.spec-runner/` は補助情報として扱う）
2. 最低限、以下を構造化する
   - **integrations**: Phase 1 で確認した連携（`[claude]` / `[github]` / `[claude, github]`）
   - **style**: Phase 1 で選択したスタイル（`ddd` / `layered`）
   - **has_frontend**: Phase 1 で確認したフロントエンドの有無（`true` / `false`）
   - **folder_structure**: Phase 2 で決定した構造（`src/` / `tests/` / `docs/` など）
   - domain_structure（style: ddd のときのみ）
   - runtime_units
   - design_policy
   - testing_policy
3. ユーザーに確認・承認を得る

## Phase 5: architecture-skill-development へ自動移行

Phase 4 が承認されたら、ユーザーにコマンドを打たせずに `architecture-skill-development` を続けて開始する。

1. `architecture-skill-development` に渡す前提（docs・architecture.yaml・確定済みフォルダ構造）を要約する
2. project 専用 skill に切り出すべき反復フローを列挙する
3. 確認なしに `architecture-skill-development` Phase 1 へ進む
4. スキル整備完了後、プロジェクト専用スキルを使って概要設計へ進む
