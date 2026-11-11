#!/usr/bin/env bash
set -e

# --- unix_script 公共库（提供 _t 翻译）---
# 本脚本在仓库内直接运行（不会被复制到用户环境），所以直接 source 拿 _t。
# 下面的颜色与打印函数在本文件里重新定义，会覆盖公共库里的同名定义。
_UXS_SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$_UXS_SMOKE_DIR/../../lib/common.sh"

# 简单的 smoke test：检查 minikube 和 kubectl 是否可用，并尝试获取集群状态
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print() { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

print "$(_t 'Starting the minikube smoke test...')"

if ! command -v minikube >/dev/null 2>&1; then
    fail "minikube $(_t 'Command not available')"
    exit 2
fi

if ! command -v kubectl >/dev/null 2>&1; then
    fail "kubectl $(_t 'Command not available')"
    exit 3
fi

print "$(_t 'Checking minikube status...')"
if minikube status >/dev/null 2>&1; then
    pass "minikube $(_t 'Running')"
    exit 0
fi

print "$(_t 'Trying to start minikube with a temporary config (timeout 60s)...')"
# 尝试以很小的资源启动以验证基本功能
minikube start --cpus=1 --memory=1024 --driver=docker &>/tmp/minikube_smoke.log &

WAIT=0
while [[ $WAIT -lt 60 ]]; do
    if minikube status >/dev/null 2>&1; then
        pass "minikube $(_t 'Started successfully and responding')"
        minikube stop &>/dev/null || true
        exit 0
    fi
    sleep 1
    WAIT=$((WAIT+1))
done

fail "minikube $(_t 'Failed to start within 60s, see /tmp/minikube_smoke.log for the log')"
exit 4
