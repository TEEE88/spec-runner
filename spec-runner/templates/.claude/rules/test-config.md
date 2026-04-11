---
description: テスト実行コマンドと種別構成。test-driven-development スキルと run-tests エージェントの両方がここを参照する。
paths: ["src/**", "tests/**"]
---

# テスト実行コマンド

> このファイルは `architecture-skill-development` でプロジェクト固有のコマンドに書き換えてください。

## 実行コマンド

```bash
# 単体テスト（高速・毎回実行）
<your-unit-test-command>

# 結合テスト
<your-integration-test-command>

# E2E テスト
<your-e2e-test-command>

# 全テスト
<your-all-test-command>

# 特定ファイル
<your-test-command> <test-file>

# カバレッジ計測
<your-test-command> --coverage
```

## テスト構成

```
tests/
  unit/        # 単体テスト（src/ と同じ構造を鏡写し）
  integration/ # 結合テスト
  e2e/         # E2E テスト
```
