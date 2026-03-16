#!/usr/bin/env bash
# spec-runner 用インストーラ（curl 用）
#
# 使い方:
#   curl -sSL https://raw.githubusercontent.com/TEEE88/spec-runner/main/install.sh | bash
#
# または wget:
#   wget -qO- https://raw.githubusercontent.com/TEEE88/spec-runner/main/install.sh | bash

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
info() { echo -e "${CYAN}ℹ${NC} $*"; }
die()  { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       spec-runner インストーラ        ║${NC}"
echo -e "${BOLD}║     フェーズ駆動 / 次のステップ方式     ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
echo ""

if command -v node &>/dev/null; then
  NODE_VERSION=$(node --version | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
  if [[ "$NODE_MAJOR" -lt 16 ]]; then
    die "Node.js 16以上が必要です（現在: v${NODE_VERSION}）\n  https://nodejs.org からインストールしてください"
  fi
  ok "Node.js v${NODE_VERSION}"
else
  die "Node.js がインストールされていません。\n  https://nodejs.org からインストールしてください"
fi

if command -v jq &>/dev/null; then
  ok "jq $(jq --version)"
else
  warn "jq が見つかりません。インストールします..."
  if command -v brew &>/dev/null; then
    brew install jq
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y jq
  elif command -v yum &>/dev/null; then
    sudo yum install -y jq
  else
    die "jq を手動でインストールしてください: https://stedolan.github.io/jq/download/"
  fi
  ok "jq インストール済み"
fi

if command -v git &>/dev/null; then
  ok "git $(git --version | awk '{print $3}')"
else
  die "git がインストールされていません"
fi

echo ""
info "npx spec-runner を実行します..."
echo ""

if command -v npx &>/dev/null; then
  npx spec-runner@latest
elif command -v npm &>/dev/null; then
  npm exec spec-runner@latest
else
  die "npm/npx が見つかりません。Node.js を再インストールしてください"
fi
