#!/usr/bin/env bash
#
# code-lint/install.sh
#
# 代码分析工具集：为 Go / Rust / Java / Python 提供静态分析、安全扫描工具的一键安装与便捷运行。
# Linux + macOS。
#
# 工具清单:
#   Go:     golangci-lint（聚合 linter）、gosec（安全扫描）
#   Rust:   clippy（官方 linter）、cargo-audit（依赖漏洞扫描）
#   Java:   spotbugs（字节码分析）、pmd（源码分析）、checkstyle（风格检查）
#   Python: ruff（极速 linter）、mypy（类型检查）、bandit（安全扫描）
#   跨语言: semgrep（多语言 SAST）
#
# 子命令：
#   install | install-go | install-rust | install-java | install-python | install-semgrep
#   go-lint | rust-lint | java-lint | py-lint | security-scan | lint-all
#   uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# ─── 工具定义 ────────────────────────────────────────────────────────────────

GO_TOOLS=("golangci-lint" "gosec")
RUST_TOOLS=("clippy" "cargo-audit")
JAVA_TOOLS=("spotbugs" "pmd" "checkstyle")
PYTHON_TOOLS=("ruff" "mypy" "bandit")
CROSS_TOOLS=("semgrep")

ALL_TOOLS=("${GO_TOOLS[@]}" "${RUST_TOOLS[@]}" "${JAVA_TOOLS[@]}" "${PYTHON_TOOLS[@]}" "${CROSS_TOOLS[@]}")

# ─── 预检 ────────────────────────────────────────────────────────────────────

preflight() {
    detect_os
    check_commands curl
}

# ─── 工具检测 ─────────────────────────────────────────────────────────────────

# 检测单个工具是否已安装
# 参数: <tool_name>
# 返回: 0=已安装, 1=未安装
tool_installed() {
    local tool="$1"
    case "$tool" in
        golangci-lint)  command_exists golangci-lint ;;
        gosec)          command_exists gosec ;;
        clippy)         command_exists rustc && rustup component list 2>/dev/null | grep -q "clippy.*installed" ;;
        cargo-audit)    command_exists cargo-audit ;;
        spotbugs)       command_exists spotbugs ;;
        pmd)            command_exists pmd ;;
        checkstyle)     command_exists checkstyle ;;
        ruff)           command_exists ruff ;;
        mypy)           command_exists mypy ;;
        bandit)         command_exists bandit ;;
        semgrep)        command_exists semgrep ;;
        *)              command_exists "$tool" ;;
    esac
}

# 统计已安装工具数
# 参数: 工具数组名
# 输出: 已安装数/总数
count_installed() {
    local -n tools_ref=$1
    local found=0
    for t in "${tools_ref[@]}"; do
        tool_installed "$t" && found=$((found + 1))
    done
    echo "$found/${#tools_ref[@]}"
}

# ─── Go 工具安装 ──────────────────────────────────────────────────────────────

install_go_tools() {
    info "📦 安装 Go 分析工具（golangci-lint + gosec）"

    if ! command_exists go; then
        warn "  ⚠️ 未检测到 go 命令，跳过 Go 工具安装"
        return 0
    fi

    # golangci-lint
    if tool_installed golangci-lint; then
        info "  ✅ golangci-lint 已安装，跳过"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
            brew install golangci-lint
        else
            info "  通过官方脚本安装 golangci-lint..."
            if curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin" 2>/dev/null; then
                success "  ✅ golangci-lint"
            else
                warn "  ⚠️ golangci-lint 安装失败"
            fi
        fi
    fi

    # gosec
    if tool_installed gosec; then
        info "  ✅ gosec 已安装，跳过"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
            brew install gosec
        else
            info "  通过 go install 安装 gosec..."
            if go install github.com/securego/gosec/v2/cmd/gosec@latest 2>/dev/null; then
                success "  ✅ gosec"
            else
                warn "  ⚠️ gosec 安装失败（可能需要设置 GOPATH/bin 到 PATH）"
            fi
        fi
    fi
}

# ─── Rust 工具安装 ─────────────────────────────────────────────────────────────

install_rust_tools() {
    info "🦀 安装 Rust 分析工具（clippy + cargo-audit）"

    if ! command_exists cargo; then
        warn "  ⚠️ 未检测到 cargo 命令，跳过 Rust 工具安装"
        return 0
    fi

    # clippy（rustup 组件）
    if tool_installed clippy; then
        info "  ✅ clippy 已安装，跳过"
    else
        info "  安装 clippy 组件..."
        if rustup component add clippy 2>/dev/null; then
            success "  ✅ clippy"
        else
            warn "  ⚠️ clippy 安装失败（需要 rustup）"
        fi
    fi

    # cargo-audit
    if tool_installed cargo-audit; then
        info "  ✅ cargo-audit 已安装，跳过"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
            brew install cargo-audit
        else
            info "  通过 cargo install 安装 cargo-audit..."
            if cargo install cargo-audit 2>/dev/null; then
                success "  ✅ cargo-audit"
            else
                warn "  ⚠️ cargo-audit 安装失败"
            fi
        fi
    fi
}

# ─── Java 工具安装 ─────────────────────────────────────────────────────────────

install_java_tools() {
    info "☕ 安装 Java 分析工具（spotbugs + pmd + checkstyle）"

    if ! command_exists java; then
        warn "  ⚠️ 未检测到 java 命令，跳过 Java 工具安装"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "  通过 Homebrew 安装..."
        for tool in spotbugs pmd checkstyle; do
            if tool_installed "$tool"; then
                info "  ✅ $tool 已安装，跳过"
            else
                if brew install "$tool"; then
                    success "  ✅ $tool"
                else
                    warn "  ⚠️ $tool 安装失败"
                fi
            fi
        done
    else
        # Linux: 通过包管理器或手动安装
        detect_pkg_manager
        local installed_any=false
        for tool in spotbugs pmd checkstyle; do
            if tool_installed "$tool"; then
                info "  ✅ $tool 已安装，跳过"
                continue
            fi
            if pkg_install "$tool" >/dev/null 2>&1; then
                success "  ✅ ${tool}（包管理器）"
                installed_any=true
            else
                warn "  ⚠️ $tool 不在仓库中"
            fi
        done
        if ! $installed_any; then
            info "  提示：Java 工具可通过 sdkman.io 或手动下载安装"
            info "  sdk install spotbugs / sdk install pmd / sdk install checkstyle"
        fi
    fi
}

# ─── Python 工具安装 ───────────────────────────────────────────────────────────

install_python_tools() {
    info "🐍 安装 Python 分析工具（ruff + mypy + bandit）"

    if ! command_exists python3; then
        warn "  ⚠️ 未检测到 python3 命令，跳过 Python 工具安装"
        return 0
    fi

    local pip_cmd="pip3"
    command_exists pip3 || pip_cmd="pip"

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "  通过 Homebrew 安装..."
        for tool in ruff mypy bandit; do
            if tool_installed "$tool"; then
                info "  ✅ $tool 已安装，跳过"
            else
                if brew install "$tool" 2>/dev/null; then
                    success "  ✅ $tool"
                else
                    # brew 可能没有 bandit，回退到 pip
                    info "  回退到 $pip_cmd 安装 $tool..."
                    if "$pip_cmd" install --user "$tool" 2>/dev/null; then
                        success "  ✅ ${tool}（pip）"
                    else
                        warn "  ⚠️ $tool 安装失败"
                    fi
                fi
            fi
        done
    else
        info "  通过 $pip_cmd 安装..."
        for tool in ruff mypy bandit; do
            if tool_installed "$tool"; then
                info "  ✅ $tool 已安装，跳过"
            else
                if "$pip_cmd" install --user "$tool" 2>/dev/null; then
                    success "  ✅ $tool"
                else
                    warn "  ⚠️ $tool 安装失败"
                fi
            fi
        done
    fi
}

# ─── Semgrep 安装 ─────────────────────────────────────────────────────────────

install_semgrep() {
    info "🔍 安装 semgrep（跨语言安全扫描）"

    if tool_installed semgrep; then
        info "  ✅ semgrep 已安装，跳过"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew install semgrep
    else
        local pip_cmd="pip3"
        command_exists pip3 || pip_cmd="pip"
        if "$pip_cmd" install --user semgrep 2>/dev/null; then
            success "  ✅ semgrep"
        else
            warn "  ⚠️ semgrep 安装失败"
        fi
    fi
}

# ─── 汇总安装 ─────────────────────────────────────────────────────────────────

install_code_lint() {
    preflight
    header "🚀 安装代码分析工具集"
    echo

    install_go_tools
    echo
    install_rust_tools
    echo
    install_java_tools
    echo
    install_python_tools
    echo
    install_semgrep

    echo
    status_code_lint
    echo
    success "🎉 代码分析工具集安装完成！"
    info "运行分析：./install.sh go-lint | rust-lint | java-lint | py-lint | security-scan | lint-all"
}

# ─── 卸载 ─────────────────────────────────────────────────────────────────────

uninstall_code_lint() {
    detect_os
    warn "code-lint 卸载说明："
    echo
    echo "  Go 工具:"
    echo "    golangci-lint: 移除 \$(go env GOPATH)/bin/golangci-lint"
    echo "    gosec:         移除 \$(go env GOPATH)/bin/gosec"
    echo
    echo "  Rust 工具:"
    echo "    clippy:        rustup component remove clippy"
    echo "    cargo-audit:   cargo uninstall cargo-audit"
    echo
    echo "  Java 工具:"
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        echo "    brew uninstall spotbugs pmd checkstyle"
    else
        echo "    sudo <pkgmgr> remove spotbugs pmd checkstyle"
    fi
    echo
    echo "  Python 工具:"
    echo "    pip3 uninstall ruff mypy bandit"
    echo
    echo "  跨语言:"
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        echo "    brew uninstall semgrep"
    else
        echo "    pip3 uninstall semgrep"
    fi
    echo
    info "（按需手动清理）"
}

# ─── 状态检查 ──────────────────────────────────────────────────────────────────

status_code_lint() {
    detect_os
    # 第一阶段：统计（不输出），用于先 emit 聚合 STATE=
    local total=0 installed=0
    local missing=()
    local t
    for t in "${GO_TOOLS[@]}" "${RUST_TOOLS[@]}" "${JAVA_TOOLS[@]}" "${PYTHON_TOOLS[@]}" "${CROSS_TOOLS[@]}"; do
        total=$((total + 1))
        if tool_installed "$t"; then
            installed=$((installed + 1))
        else
            missing+=("$t")
        fi
    done

    # 聚合主状态：全部→installed；部分→installed（extra 标注缺失）；无→not_installed
    local state human_msg
    if [[ $installed -ge $total ]]; then
        state="installed"
        human_msg="  ${GREEN}✅ 全部已安装 ($installed/$total)${NC}"
    elif [[ $installed -gt 0 ]]; then
        state="installed"
        human_msg="  ${YELLOW}⚠️  部分已安装 ($installed/$total)${NC}"
    else
        state="not_installed"
        human_msg="  ${RED}❌ 未安装任何工具${NC}"
    fi
    emit_status "$state" "$human_msg"
    emit_extra "installed=$installed/$total"
    if [[ ${#missing[@]} -gt 0 ]]; then
        local missing_csv
        # shellcheck disable=SC2086
        missing_csv=$(IFS=,; echo "${missing[*]}")
        emit_extra "missing=$missing_csv"
    fi

    # 第二阶段：人类模式详情（逐工具 ✅/❌ 清单）
    if ! uxs_is_machine_mode; then
        header "📊 代码分析工具状态"
        echo

        # Go
        printf "  %-8s" "Go:"
        for t in "${GO_TOOLS[@]}"; do
            if tool_installed "$t"; then
                printf " ${GREEN}%s ✅${NC}" "$t"
            else
                printf " ${RED}%s ❌${NC}" "$t"
            fi
        done
        echo

        # Rust
        printf "  %-8s" "Rust:"
        for t in "${RUST_TOOLS[@]}"; do
            if tool_installed "$t"; then
                printf " ${GREEN}%s ✅${NC}" "$t"
            else
                printf " ${RED}%s ❌${NC}" "$t"
            fi
        done
        echo

        # Java
        printf "  %-8s" "Java:"
        for t in "${JAVA_TOOLS[@]}"; do
            if tool_installed "$t"; then
                printf " ${GREEN}%s ✅${NC}" "$t"
            else
                printf " ${RED}%s ❌${NC}" "$t"
            fi
        done
        echo

        # Python
        printf "  %-8s" "Python:"
        for t in "${PYTHON_TOOLS[@]}"; do
            if tool_installed "$t"; then
                printf " ${GREEN}%s ✅${NC}" "$t"
            else
                printf " ${RED}%s ❌${NC}" "$t"
            fi
        done
        echo

        # 跨语言
        printf "  %-8s" "跨语言:"
        for t in "${CROSS_TOOLS[@]}"; do
            if tool_installed "$t"; then
                printf " ${GREEN}%s ✅${NC}" "$t"
            else
                printf " ${RED}%s ❌${NC}" "$t"
            fi
        done
        echo
    fi
}

# ─── 便捷运行：lint-all ───────────────────────────────────────────────────────

lint_all() {
    local target="${1:-.}"
    local has_error=false

    header "🔍 全语言代码分析：$target"
    echo

    # 检测语言并运行
    if find "$target" -maxdepth 3 -name "*.go" -print -quit 2>/dev/null | grep -q .; then
        bash "$SCRIPT_DIR/scripts/go-lint.sh" "$target" || has_error=true
        echo
    fi

    if find "$target" -maxdepth 3 -name "*.rs" -print -quit 2>/dev/null | grep -q .; then
        bash "$SCRIPT_DIR/scripts/rust-lint.sh" "$target" || has_error=true
        echo
    fi

    if find "$target" -maxdepth 3 \( -name "*.java" -o -name "pom.xml" -o -name "build.gradle" \) -print -quit 2>/dev/null | grep -q .; then
        bash "$SCRIPT_DIR/scripts/java-lint.sh" "$target" || has_error=true
        echo
    fi

    if find "$target" -maxdepth 3 -name "*.py" -print -quit 2>/dev/null | grep -q .; then
        bash "$SCRIPT_DIR/scripts/py-lint.sh" "$target" || has_error=true
        echo
    fi

    # 始终运行 semgrep 安全扫描
    if tool_installed semgrep; then
        bash "$SCRIPT_DIR/scripts/security-scan.sh" "$target" || has_error=true
    fi

    if $has_error; then
        error "分析完成，存在错误"
        return 1
    else
        success "🎉 所有分析通过"
    fi
}

# ─── 帮助 ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
用法: $0 {install|install-go|install-rust|install-java|install-python|install-semgrep|go-lint|rust-lint|java-lint|py-lint|security-scan|lint-all|uninstall|status|help}

安装类:
  install          安装全部代码分析工具（默认动作）
  install-go       仅安装 Go 工具（golangci-lint + gosec）
  install-rust     仅安装 Rust 工具（clippy + cargo-audit）
  install-java     仅安装 Java 工具（spotbugs + pmd + checkstyle）
  install-python   仅安装 Python 工具（ruff + mypy + bandit）
  install-semgrep  仅安装 semgrep

运行类:
  go-lint [path]       运行 Go 代码分析
  rust-lint [path]     运行 Rust 代码分析
  java-lint [path]     运行 Java 代码分析
  py-lint [path]       运行 Python 代码分析
  security-scan [path] 运行跨语言安全扫描（semgrep）
  lint-all [path]      自动检测语言并运行所有适用的分析

管理类:
  uninstall        显示卸载说明
  status           查看各工具安装状态
  help             显示此帮助
EOF
}

# ─── 主入口 ────────────────────────────────────────────────────────────────────

main() {
    local action="${1:-install}"
    detect_os

    case "$action" in
        install)            install_code_lint ;;
        install-go)         preflight; install_go_tools ;;
        install-rust)       preflight; install_rust_tools ;;
        install-java)       preflight; install_java_tools ;;
        install-python)     preflight; install_python_tools ;;
        install-semgrep)    preflight; install_semgrep ;;
        go-lint)            bash "$SCRIPT_DIR/scripts/go-lint.sh" "${2:-.}" ;;
        rust-lint)          bash "$SCRIPT_DIR/scripts/rust-lint.sh" "${2:-.}" ;;
        java-lint)          bash "$SCRIPT_DIR/scripts/java-lint.sh" "${2:-.}" ;;
        py-lint)            bash "$SCRIPT_DIR/scripts/py-lint.sh" "${2:-.}" ;;
        security-scan)      bash "$SCRIPT_DIR/scripts/security-scan.sh" "${2:-.}" ;;
        lint-all)           lint_all "${2:-.}" ;;
        uninstall)          uninstall_code_lint ;;
        status)             status_code_lint ;;
        help|--help|-h)     usage ;;
        *)                  error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
