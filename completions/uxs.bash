#!/usr/bin/env bash
# unix_script / uxs Bash 自动补全（注册表驱动）
# 模块清单运行时从仓库 .manifest 动态生成，新增模块自动进补全。
# 用法：source completions/uxs.bash

_uxs_completions() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local comp_dir repo_root cat_dir d
    comp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd "$comp_dir/.." && pwd)"

    # 第一个参数：模块名 + 全局选项
    if [[ $COMP_CWORD -eq 1 ]]; then
        local modules="" globals
        for cat_dir in services essentials dev-tools ai-tools sys-tools; do
            [[ -d "$repo_root/$cat_dir" ]] || continue
            for d in "$repo_root/$cat_dir"/*/; do
                if [[ -f "$d/.manifest" ]]; then
                    modules="$modules $(basename "$d")"
                fi
            done
        done
        globals="--status --status-json --list --list-modules --list-categories --dry-run --no-deps --version --help update check-update cli uninstall-cli doctor scaffold export apply completions"
        COMPREPLY=( $(compgen -W "$modules $globals" -- "$cur") )
        return 0
    fi

    # 第二个参数：子命令（解析模块 usage 行 {a|b|c} 枚举；无枚举回退默认四件套）
    if [[ $COMP_CWORD -eq 2 ]]; then
        local mod="${COMP_WORDS[1]}" script="" subcmds="" usage_line
        for cat_dir in services essentials dev-tools ai-tools sys-tools; do
            if [[ -f "$repo_root/$cat_dir/$mod/install.sh" ]]; then
                script="$repo_root/$cat_dir/$mod/install.sh"
                break
            fi
        done
        if [[ -n "$script" ]]; then
            usage_line=$(grep -m1 '用法:' "$script" 2>/dev/null || true)
            if [[ "$usage_line" == *"{"*"}"* ]]; then
                subcmds=$(echo "$usage_line" | sed 's/.*{//;s/}.*//' | tr '|' ' ')
            fi
        fi
        [[ -z "$subcmds" ]] && subcmds="install uninstall status help"
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi

    return 0
}

complete -F _uxs_completions uxs
complete -F _uxs_completions install.sh
