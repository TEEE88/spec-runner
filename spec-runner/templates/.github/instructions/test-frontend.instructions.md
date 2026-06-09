---
applyTo: "frontend/src/**,frontend/tests/**"
---

# フロントエンドテスト実行コマンド

> このファイルは `architecture-skill-development` でプロジェクト固有のコマンドに書き換えてください。

## 実行コマンド

```bash
# 単体テスト（高速・毎回実行）
<your-frontend-unit-test-command>

# 結合テスト
<your-frontend-integration-test-command>

# E2E テスト
<your-frontend-e2e-test-command>

# 全テスト
<your-frontend-all-test-command>

# 特定ファイル
<your-frontend-test-command> <test-file>

# カバレッジ計測
<your-frontend-test-command> --coverage
```

## テスト構成

```
frontend/tests/
  unit/        # 単体テスト（frontend/src/ と同じ構造を鏡写し）
  integration/ # 結合テスト
  e2e/         # E2E テスト
```