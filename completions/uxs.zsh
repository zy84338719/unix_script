#compdef uxs

# unix_script / uxs Zsh 自动补全（注册表驱动）
# 模块清单与描述运行时从仓库 .manifest 动态生成，新增模块自动进补全。
# 用法：source completions/uxs.zsh

_uxs() {
    local -a modules globals subcmds
    local comp_file repo_root mf mod label desc line script
    comp_file=${(%):-%x}
    repo_root=${comp_file:A:h}/..

    # 模块清单：扫描各分类目录 .manifest（与 uxs list 同源）
    modules=()
    for mf in "$repo_root"/services/*/.manifest(N) \
              "$repo_root"/essentials/*/.manifest(N) \
              "$repo_root"/dev-tools/*/.manifest(N) \
              "$repo_root"/ai-tools/*/.manifest(N) \
              "$repo_root"/sys-tools/*/.manifest(N); do
        mod=${mf:h:t}
        desc=$(grep -m1 '^DESC=' "$mf" 2>/dev/null | cut -d= -f2-)
        label=$(grep -m1 '^LABEL=' "$mf" 2>/dev/null | cut -d= -f2-)
        modules+=("${mod}:${desc:-$label}")
    done

    globals=(
        'install:安装模块'
        'remove:卸载模块'
        'status:查看状态（--json 机器可读）'
        'list:列出模块（--full / --grouped / --category）'
        'search:搜索模块（名称/别名/描述）'
        'info:查看模块明细'
        'doctor:环境诊断'
        'export:导出已装模块为 profile'
        'apply:从 profile 应用配置'
        'update:更新到最新版（--check 只查不更）'
        'scaffold:创建新模块模板'
        'completions:安装 Tab 补全'
        'cli:安装/卸载全局命令 uxs'
        'help:帮助信息'
        'version:查看版本'
        '--list-all:全量模块清单（TSV）'
    )

    _arguments -C \
        '1: :->first_arg' \
        '2: :->second_arg' \
        '*:: :->rest'

    case $state in
        first_arg)
            _describe -t modules '模块' modules
            _describe -t globals '全局选项' globals
            ;;
        second_arg)
            local m=$words[2]
            script=$(print -r -- "$repo_root"/*/"$m"/install.sh(N) | head -1)
            subcmds=()
            if [[ -n $script ]]; then
                line=$(grep -m1 '用法:' "$script" 2>/dev/null)
                if [[ $line == *\{*}* ]]; then
                    subcmds=( ${(s:|:)${${line##*\{}%%\}*}} )
                fi
            fi
            (( $#subcmds )) || subcmds=(install uninstall status help)
            _describe -t subcmds '子命令' subcmds
            ;;
    esac
}

_uxs "$@"
