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
        golangci-lint)  os_has_cmd golangci-lint ;;
        gosec)          os_has_cmd gosec ;;
        clippy)         os_has_cmd rustc && rustup component list 2>/dev/null | grep -q "clippy.*installed" ;;
        cargo-audit)    os_has_cmd cargo-audit ;;
        spotbugs)       os_has_cmd spotbugs ;;
        pmd)            os_has_cmd pmd ;;
        checkstyle)     os_has_cmd checkstyle ;;
        ruff)           os_has_cmd ruff ;;
        mypy)           os_has_cmd mypy ;;
        bandit)         os_has_cmd bandit ;;
        semgrep)        os_has_cmd semgrep ;;
        *)              os_has_cmd "$tool" ;;
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
    info "$(_t 'Install Go analysis tools (golangci-lint + gosec)')"

    if ! os_has_cmd go; then
        warn "  $(_t 'go command not detected, skipping Go tool installation')"
        return 0
    fi

    # golangci-lint
    if tool_installed golangci-lint; then
        info "  $(_t 'golangci-lint already installed, skipping')"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
            brew install golangci-lint
        else
            info "  $(_t 'Installing golangci-lint via the official script...')"
            if curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin" 2>/dev/null; then
                success "  ✅ golangci-lint"
            else
                warn "  $(_t 'golangci-lint installation failed')"
            fi
        fi
    fi

    # gosec
    if tool_installed gosec; then
        info "  $(_t 'gosec already installed, skipping')"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
            brew install gosec
        else
            info "  $(_t 'Installing gosec via go install...')"
            if go install github.com/securego/gosec/v2/cmd/gosec@latest 2>/dev/null; then
                success "  ✅ gosec"
            else
                warn "  $(_t 'gosec installation failed (you may need to add GOPATH/bin to PATH)')"
            fi
        fi
    fi
}

# ─── Rust 工具安装 ─────────────────────────────────────────────────────────────

install_rust_tools() {
    info "$(_t 'Install Rust analysis tools (clippy + cargo-audit)')"

    if ! os_has_cmd cargo; then
        warn "  $(_t 'cargo command not detected, skipping Rust tool installation')"
        return 0
    fi

    # clippy（rustup 组件）
    if tool_installed clippy; then
        info "  $(_t 'clippy already installed, skipping')"
    else
        info "  $(_t 'Installing the clippy component...')"
        if rustup component add clippy 2>/dev/null; then
            success "  ✅ clippy"
        else
            warn "  $(_t 'clippy installation failed (rustup is required)')"
        fi
    fi

    # cargo-audit
    if tool_installed cargo-audit; then
        info "  $(_t 'cargo-audit already installed, skipping')"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
            brew install cargo-audit
        else
            info "  $(_t 'Installing cargo-audit via cargo install...')"
            if cargo install cargo-audit 2>/dev/null; then
                success "  ✅ cargo-audit"
            else
                warn "  $(_t 'cargo-audit installation failed')"
            fi
        fi
    fi
}

# ─── Java 工具安装 ─────────────────────────────────────────────────────────────

install_java_tools() {
    info "$(_t 'Install Java analysis tools (spotbugs + pmd + checkstyle)')"

    if ! os_has_cmd java; then
        warn "  $(_t 'java command not detected, skipping Java tool installation')"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        info "  $(_t 'Installing via Homebrew...')"
        for tool in spotbugs pmd checkstyle; do
            if tool_installed "$tool"; then
                info "  $(_tf '%s already installed, skipping' "$tool")"
            else
                if brew install "$tool"; then
                    success "  ✅ $tool"
                else
                    warn "  $(_tf '%s installation failed' "$tool")"
                fi
            fi
        done
    else
        # Linux: 通过包管理器或手动安装
        detect_pkg_manager
        local installed_any=false
        for tool in spotbugs pmd checkstyle; do
            if tool_installed "$tool"; then
                info "  $(_tf '%s already installed, skipping' "$tool")"
                continue
            fi
            if pkg_install "$tool" >/dev/null 2>&1; then
                success "  $(_tf '%s (package manager)' "${tool}")"
                installed_any=true
            else
                warn "  $(_tf '%s is not available in the repository' "$tool")"
            fi
        done
        if ! $installed_any; then
            info "  $(_t 'Tip: Java tools can be installed via sdkman.io or by downloading them manually')"
            info "  sdk install spotbugs / sdk install pmd / sdk install checkstyle"
        fi
    fi
}

# ─── Python 工具安装 ───────────────────────────────────────────────────────────

install_python_tools() {
    info "$(_t 'Install Python analysis tools (ruff + mypy + bandit)')"

    if ! os_has_cmd python3; then
        warn "  $(_t 'python3 command not detected, skipping Python tool installation')"
        return 0
    fi

    local pip_cmd="pip3"
    os_has_cmd pip3 || pip_cmd="pip"

    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        info "  $(_t 'Installing via Homebrew...')"
        for tool in ruff mypy bandit; do
            if tool_installed "$tool"; then
                info "  $(_tf '%s already installed, skipping' "$tool")"
            else
                if brew install "$tool" 2>/dev/null; then
                    success "  ✅ $tool"
                else
                    # brew 可能没有 bandit，回退到 pip
                    info "  $(_tf 'Falling back to %s to install %s...' "$pip_cmd" "$tool")"
                    if "$pip_cmd" install --user "$tool" 2>/dev/null; then
                        success "  $(_tf '%s (pip)' "${tool}")"
                    else
                        warn "  $(_tf '%s installation failed' "$tool")"
                    fi
                fi
            fi
        done
    else
        info "  $(_tf 'Installing via %s...' "$pip_cmd")"
        for tool in ruff mypy bandit; do
            if tool_installed "$tool"; then
                info "  $(_tf '%s already installed, skipping' "$tool")"
            else
                if "$pip_cmd" install --user "$tool" 2>/dev/null; then
                    success "  ✅ $tool"
                else
                    warn "  $(_tf '%s installation failed' "$tool")"
                fi
            fi
        done
    fi
}

# ─── Semgrep 安装 ─────────────────────────────────────────────────────────────

install_semgrep() {
    info "$(_t 'Install semgrep (cross-language security scanning)')"

    if tool_installed semgrep; then
        info "  $(_t 'semgrep already installed, skipping')"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        brew install semgrep
    else
        local pip_cmd="pip3"
        os_has_cmd pip3 || pip_cmd="pip"
        if "$pip_cmd" install --user semgrep 2>/dev/null; then
            success "  ✅ semgrep"
        else
            warn "  $(_t 'semgrep installation failed')"
        fi
    fi
}

# ─── 汇总安装 ─────────────────────────────────────────────────────────────────

install_code_lint() {
    preflight
    header "$(_t 'Install the code analysis toolset')"
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
    success "$(_t 'Code analysis toolset installation completed!')"
    info "$(_t 'Run analysis: ./install.sh go-lint | rust-lint | java-lint | py-lint | security-scan | lint-all')"
}

# ─── 卸载 ─────────────────────────────────────────────────────────────────────

uninstall_code_lint() {
    detect_os
    warn "code-lint $(_t 'Uninstall instructions:')"
    echo
    echo "  Go $(_t 'Tools:')"
    echo "    golangci-lint: $(_t 'Remove') \$(go env GOPATH)/bin/golangci-lint"
    echo "    gosec:         $(_t 'Remove') \$(go env GOPATH)/bin/gosec"
    echo
    echo "  Rust $(_t 'Tools:')"
    echo "    clippy:        rustup component remove clippy"
    echo "    cargo-audit:   cargo uninstall cargo-audit"
    echo
    echo "  Java $(_t 'Tools:')"
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        echo "    brew uninstall spotbugs pmd checkstyle"
    else
        echo "    sudo <pkgmgr> remove spotbugs pmd checkstyle"
    fi
    echo
    echo "  Python $(_t 'Tools:')"
    echo "    pip3 uninstall ruff mypy bandit"
    echo
    echo "  $(_t 'Cross-language:')"
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        echo "    brew uninstall semgrep"
    else
        echo "    pip3 uninstall semgrep"
    fi
    echo
    info "$(_t '(clean up manually as needed)')"
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
        human_msg="  ${GREEN}$(_tf 'All installed (%s/%s)' "$installed" "$total")${NC}"
    elif [[ $installed -gt 0 ]]; then
        state="installed"
        human_msg="  ${YELLOW}$(_tf 'Partially installed (%s/%s)' "$installed" "$total")${NC}"
    else
        state="not_installed"
        human_msg="  ${RED}$(_t 'No tools installed')${NC}"
    fi
    uxs_emit_status "$state" "$human_msg"
    uxs_emit_extra "installed=$installed/$total"
    if [[ ${#missing[@]} -gt 0 ]]; then
        local missing_csv
        # shellcheck disable=SC2086
        missing_csv=$(IFS=,; echo "${missing[*]}")
        uxs_emit_extra "missing=$missing_csv"
    fi

    # 第二阶段：人类模式详情（逐工具 ✅/❌ 清单）
    if ! uxs_is_machine_mode; then
        header "$(_t 'Code analysis tool status')"
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
        printf "  %-8s" "$(_t 'Cross-language:')"
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

    header "$(_tf 'Full-language code analysis: %s' "$target")"
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
        error "$(_t 'Analysis completed with errors')"
        return 1
    else
        success "$(_t 'All analyses passed')"
    fi
}

# ─── 帮助 ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
用法: $0 {install|install-go|install-rust|install-java|install-python|install-semgrep|go-lint|rust-lint|java-lint|py-lint|security-scan|lint-all|uninstall|status|help}

$(_t 'Install commands:')
  install          $(_t 'Install all code analysis tools (default action)')
  install-go       $(_t 'Install only Go tools (golangci-lint + gosec)')
  install-rust     $(_t 'Install only Rust tools (clippy + cargo-audit)')
  install-java     $(_t 'Install only Java tools (spotbugs + pmd + checkstyle)')
  install-python   $(_t 'Install only Python tools (ruff + mypy + bandit)')
  install-semgrep  $(_t 'Install only semgrep')

$(_t 'Run commands:')
  go-lint [path]       $(_t 'Run Go code analysis')
  rust-lint [path]     $(_t 'Run Rust code analysis')
  java-lint [path]     $(_t 'Run Java code analysis')
  py-lint [path]       $(_t 'Run Python code analysis')
  security-scan [path] $(_t 'Run cross-language security scanning (semgrep)')
  lint-all [path]      $(_t 'Auto-detect the language and run all applicable analyses')

$(_t 'Management commands:')
  uninstall        $(_t 'Show the uninstall instructions')
  status           $(_t 'Show the installation status of each tool')
  help             $(_t 'Show this help message')
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
        *)                  error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
