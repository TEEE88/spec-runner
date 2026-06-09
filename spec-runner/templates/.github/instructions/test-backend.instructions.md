---
applyTo: "backend/src/**,backend/tests/**"
---

# バックエンドテスト実行コマンド

> このファイルは `architecture-skill-development` でプロジェクト固有のコマンドに書き換えてください。

## 実行コマンド

```bash
# 単体テスト（高速・毎回実行）
<your-backend-unit-test-command>

# 結合テスト
<your-backend-integration-test-command>

# E2E テスト
<your-backend-e2e-test-command>

# 全テスト
<your-backend-all-test-command>

# 特定ファイル
<your-backend-test-command> <test-file>

# カバレッジ計測
<your-backend-test-command> --coverage
```

## テスト構成

```
backend/tests/
  unit/        # 単体テスト（backend/src/ と同じ構造を鏡写し）
  integration/ # 結合テスト
  e2e/         # E2E テスト
```