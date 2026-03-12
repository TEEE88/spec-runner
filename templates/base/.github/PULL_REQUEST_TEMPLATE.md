## 対象ユースケース

<!-- ./scripts/spec-runner.sh status の出力を貼り付ける -->

## 変更の種別

- [ ] 新規機能（feature/uc-）
- [ ] 通常修正（fix/）
- [ ] 緊急修正（hotfix/）

---

## ドキュメント更新チェック

<!-- 変更内容に応じてチェックしてください。不要な項目は N/A と書く -->

| ドキュメント | 更新済み | パス |
|------------|---------|------|
| ドメインモデル設計 | [ ] | docs/detailed/*/domain.md |
| ユースケース設計 | [ ] | docs/detailed/*/usecase.md |
| テーブル設計 | [ ] | docs/detailed/*/table.md |
| インフラ設計 | [ ] | docs/detailed/*/infra.md |
| テスト設計 | [ ] | docs/test-design/*.md |
| glossary.md | [ ] | docs/glossary.md |
| ADR | [ ] / N/A | docs/adr/XXX-*.md |

---

## レビュアー向け読み順

1. **設計ドキュメント** `docs/detailed/<UC名>/` — 何を作るか
2. **ADR** `docs/adr/` — なぜその設計か（該当する場合）
3. **テスト設計** `docs/test-design/<UC名>.md` — 何を検証するか
4. **テストコード** — 振る舞いの確認
5. **実装コード** — 設計との整合性確認

---

## hotfix の場合（追加記入）

- 影響ユースケース:
- 修正内容の要約:
- debt.md への記録: [ ] 完了
