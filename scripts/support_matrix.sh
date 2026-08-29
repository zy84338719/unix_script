#!/usr/bin/env bash
#
# scripts/support_matrix.sh — 渲染/回写「支持的操作系统 + CI 状态」表格
#
# 数据源：
#   1. .github/workflows/ci.yml 的矩阵定义（静态：支持哪些系统）
#   2. GitHub API：main 分支最近一次已完成 CI run 的各 job 结论（动态：编译/测试情况）
#
# 用法:
#   support_matrix.sh render            # markdown 输出到 stdout
#   support_matrix.sh update <readme>   # 回写 README 中 <!-- SUPPORT-MATRIX:START/END --> 区间
#
# 状态查询需要 jq + 网络（GH_TOKEN/GITHUB_TOKEN 可选，私有库必填）；不可用时状态列回退 ⏳。
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_YAML="$REPO_ROOT/.github/workflows/ci.yml"
REPO_SLUG="${GITHUB_REPOSITORY:-zy84338719/unix_script}"

# ---------- 矩阵解析（纯 awk，不依赖 yq） ----------
# 输出: <job>\t<distro>\t<image>\t<expect_family>
parse_matrix() {
    awk '
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
        /^  [a-z][a-z0-9_-]*:$/ { job=$1; sub(/:$/,"",job) }
        /^[ \t]+-[ \t]+distro:/    { pd=trim($0); sub(/^[^:]*:[ \t]*/,"",pd); sub(/[ \t]+#.*/,"",pd) }
        /^[ \t]+image:/            { img=trim($0); sub(/^[^:]*:[ \t]*/,"",img) }
        /^[ \t]+expect_family:/ && pd!="" && img!="" {
            fam=trim($0); sub(/^[^:]*:[ \t]*/,"",fam)
            print job "\t" pd "\t" img "\t" fam
            pd=""; img=""
        }
    ' "$CI_YAML"
}

# ---------- 显示名与包管理族 ----------
display_name() {
    case "$1" in
        ubuntu-*)            echo "Ubuntu ${1#ubuntu-}" ;;
        debian-*)            echo "Debian ${1#debian-}" ;;
        fedora)              echo "Fedora" ;;
        centos-stream9)      echo "CentOS Stream 9" ;;
        almalinux-9)         echo "AlmaLinux 9" ;;
        rocky-9)             echo "Rocky Linux 9" ;;
        opensuse-tumbleweed) echo "openSUSE Tumbleweed" ;;
        arch)                echo "Arch Linux" ;;
        alpine)              echo "Alpine Linux" ;;
        kylin-v10-sp3)       echo "银河麒麟 V10 SP3" ;;
        uos-v20)             echo "统信 UOS V20" ;;
        openeuler-24.03-lts) echo "openEuler 24.03 LTS" ;;
        deepin-23)           echo "deepin 23" ;;
        openkylin)           echo "openKylin" ;;
        *)                   echo "$1" ;;
    esac
}
family_pm() {
    case "$1" in
        debian) echo "apt" ;;
        rhel)   echo "dnf/yum" ;;
        suse)   echo "zypper" ;;
        arch)   echo "pacman" ;;
        alpine) echo "apk" ;;
        *)      echo "—" ;;
    esac
}

# ---------- CI 状态查询（容错：任何失败都回退 ⏳） ----------
fetch_statuses() {
    command -v jq >/dev/null 2>&1 || return 0
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local auth=()
    [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
    # bash 3.2 空数组在 set -u 下视为未绑定，用展开守卫
    local curl_args=()
    curl_args=(${auth[@]+"${auth[@]}"})
    local api="https://api.github.com" run_id
    run_id=$(curl -sfL "${curl_args[@]+"${curl_args[@]}"}" \
        "$api/repos/$REPO_SLUG/actions/workflows/ci.yml/runs?branch=main&per_page=10" 2>/dev/null |
        jq -r '[.workflow_runs[] | select(.status=="completed")][0].id // empty' 2>/dev/null) || return 0
    [ -n "$run_id" ] || return 0
    curl -sfL "${curl_args[@]+"${curl_args[@]}"}" "$api/repos/$REPO_SLUG/actions/runs/$run_id/jobs?per_page=100" 2>/dev/null |
        jq -r '.jobs[] | .name + "\t" + (.conclusion // "pending")' 2>/dev/null || true
}

status_icon() {  # <job 全名> <状态映射>
    local job="$1" map="$2" c
    c=$(printf '%s\n' "$map" | awk -F'\t' -v j="$job" '$1==j{print $2; exit}')
    case "${c:-}" in
        success)             echo "✅" ;;
        failure)             echo "❌" ;;
        cancelled|timed_out) echo "🚫" ;;
        skipped)             echo "⏭️" ;;
        *)                   echo "⏳" ;;
    esac
}

render() {
    local map
    map=$(fetch_statuses)
    echo '## 🖥️ 支持的操作系统与 CI 状态'
    echo
    # shellcheck disable=SC2016  # 反引号是字面 markdown
    echo '> 状态列 = main 分支最近一次完成的 CI run 中对应 job 的结论，由 `support-matrix` 任务自动刷新。'
    echo
    echo '| 分类 | 系统 | 镜像 / 版本 | 包管理 | CI |'
    echo '|------|------|-------------|--------|:--:|'
    echo "| 实机 | Ubuntu（runner 内置） | ubuntu-latest | apt | $(status_icon "静态检查 / ubuntu-latest" "$map") |"
    echo "| 实机 | macOS（runner 内置） | macos-latest | brew | $(status_icon "静态检查 / macos-latest" "$map") |"
    while IFS=$'\t' read -r job d img fam; do
        [ "$job" = "install-container" ] || continue
        echo "| 容器 | $(display_name "$d") | \`$img\` | $(family_pm "$fam") | $(status_icon "包解析 / 容器 / $d" "$map") |"
    done < <(parse_matrix)
    while IFS=$'\t' read -r job d img fam; do
        [ "$job" = "install-container-domestic" ] || continue
        echo "| 国产化* | $(display_name "$d") | \`$img\` | $(family_pm "$fam") | $(status_icon "国产化平台验证 / $d" "$map") |"
    done < <(parse_matrix)
    echo
    printf '%s\n' '> \* 国产化社区镜像为尽力而为（continue-on-error）：结果记入报告，不阻塞质量门禁。'
}

update_readme() {
    local readme="$1" tmp rendered
    rendered=$(mktemp)
    render > "$rendered"
    tmp=$(mktemp)
    RENDERED_FILE="$rendered" awk '
        BEGIN{skip=0}
        /<!-- SUPPORT-MATRIX:START/{
            print
            while ((getline line < ENVIRON["RENDERED_FILE"]) > 0) print line
            skip=1; next
        }
        /<!-- SUPPORT-MATRIX:END/{skip=0; next}
        skip==0{print}
    ' "$readme" > "$tmp"
    rm -f "$rendered"
    mv "$tmp" "$readme"
    echo "支持矩阵已回写 $readme"
}

case "${1:-render}" in
    render) render ;;
    update) [ -n "${2:-}" ] || { echo "用法: $0 update <readme>"; exit 1; }; update_readme "$2" ;;
    *) echo "用法: $0 render|update <readme>"; exit 1 ;;
esac
