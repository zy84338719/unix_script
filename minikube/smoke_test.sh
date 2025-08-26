#!/usr/bin/env bash
set -e

# 简单的 smoke test：检查 minikube 和 kubectl 是否可用，并尝试获取集群状态
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print() { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

print "开始 minikube smoke test..."

if ! command -v minikube >/dev/null 2>&1; then
    fail "minikube 命令不可用"
    exit 2
fi

if ! command -v kubectl >/dev/null 2>&1; then
    fail "kubectl 命令不可用"
    exit 3
fi

print "检查 minikube status..."
if minikube status >/dev/null 2>&1; then
    pass "minikube 正在运行"
    exit 0
fi

print "尝试以临时配置启动 minikube（超时 60s）..."
# 尝试以很小的资源启动以验证基本功能
minikube start --cpus=1 --memory=1024 --driver=docker &>/tmp/minikube_smoke.log &
PID=$!

WAIT=0
while [[ $WAIT -lt 60 ]]; do
    if minikube status >/dev/null 2>&1; then
        pass "minikube 成功启动并响应"
        minikube stop &>/dev/null || true
        exit 0
    fi
    sleep 1
    WAIT=$((WAIT+1))
done

fail "minikube 在 60s 内未能启动，查看 /tmp/minikube_smoke.log 获取日志"
exit 4
