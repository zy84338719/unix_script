#!/usr/bin/env bash
#
# lib/profile.sh
#
# 配置导出/应用（阶段 D）。把「哪些模块已装 + 各自关键配置」导出为可 git 友好的纯文本
# profile，在新机器上 `uxs apply` 一键复现。
#
# 依赖：lib/deps.sh 的 topo_sort_all（apply 按依赖序安装）、lib/status.sh 的
#       module_status_machine / module_status_raw（判定已装状态 + 读取 EXTRA）。
#
# profile 行格式：  <模块名> [key=value ...]   # 可选人类注释
#   - 整行 # / ## 开头为注释/分组（apply 忽略）
#   - 模块名后可跟 key=value 配置（apply 时注入 UXS_CONFIG_<KEY>=<val>）
#   - 删行 = apply 时不安装该模块
#
# 详见 docs/superpowers/specs/2026-08-07-status-contract-deps-profile-design.md 阶段 D。
#

# 幂等保护
if [[ -n "${_PROFILE_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_PROFILE_SH_LOADED=1

DEFAULT_PROFILE_DIR="${HOME}/.config/unix_script"
DEFAULT_PROFILE_FILE="${DEFAULT_PROFILE_DIR}/profile.txt"

# 导出当前已安装/已配置模块为 profile 文件。
# 用法: export_profile [输出文件]   （默认 ${DEFAULT_PROFILE_FILE}）
export_profile() {
    local out="${1:-$DEFAULT_PROFILE_FILE}"
    local out_dir
    out_dir="$(dirname "$out")"
    [[ -d "$out_dir" ]] || mkdir -p "$out_dir"

    {
        echo "# unix_script profile"
        echo "# 导出于: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# 用法: uxs apply \"$out\"            应用本 profile"
        echo "#       uxs apply \"$out\" --force     强制重装已就绪模块"
        echo "#       uxs apply \"$out\" --dry-run   预览（不实际执行）"
        echo "# 行格式: <模块名> [key=value ...]   # 删行=不应用；# 开头为注释"
        echo ""

        # 按拓扑序导出（被依赖者在前；apply 时安装序自然正确）
        local order mod
        order=$(topo_sort_all)
        local last_cat=""
        for mod in $order; do
            uxs_module_visible "$mod" || continue   # 只导出本机适用模块（不适用模块在本机无 profile 意义）
            local state
            state=$(module_status_machine "$mod")
            case "$state" in
                installed|installed:running|installed:stopped|configured) ;;
                *) continue ;;   # 未安装/未配置/不适用：不导出
            esac

            # 分类分组注释（人类友好，apply 忽略 ##）
            local cat label
            cat=$(registry_category "$mod")
            label=$(registry_label "$mod")
            if [[ "$cat" != "$last_cat" ]]; then
                echo "## ${cat}"
                last_cat="$cat"
            fi

            # 按 EXPORTABLE 白名单过滤 EXTRA=key=value
            local allow filtered=""
            allow=$(registry_exportable "$mod")
            local raw kv k
            raw=$(module_status_raw "$mod")
            while IFS= read -r kv; do
                case "$kv" in
                    EXTRA=*)
                        kv="${kv#EXTRA=}"
                        k="${kv%%=*}"
                        if [[ -n "$k" && " $allow " == *" $k "* ]]; then
                            filtered="${filtered:+$filtered }$kv"
                        fi
                        ;;
                esac
            done <<< "$raw"

            if [[ -n "$filtered" ]]; then
                printf '%s %s   # %s\n' "$mod" "$filtered" "$label"
            else
                printf '%s   # %s\n' "$mod" "$label"
            fi
        done
    } > "$out"
    success "已导出 profile：$out"
    info "在新机器复现：uxs apply \"$out\""
}

# 应用 profile：按拓扑序安装未就绪模块，透传 key=value 配置。
# 用法: apply_profile [文件] [--force] [--dry-run]
apply_profile() {
    local file="$DEFAULT_PROFILE_FILE"
    local force=false dry=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)   force=true; shift ;;
            --dry-run) dry=true; shift ;;
            -h|--help) echo "用法: apply_profile [文件] [--force] [--dry-run]"; return 0 ;;
            *)         file="$1"; shift ;;
        esac
    done
    if [[ ! -f "$file" ]]; then
        error "profile 文件不存在：$file"
        return 1
    fi

    # 1. 解析 profile（平行数组存 模块名/配置，bash 3.2 兼容）
    local -a p_mods=() p_cfgs=()
    local line mod cfg content
    while IFS= read -r line || [[ -n "$line" ]]; do
        content="${line%%#*}"                 # 去注释
        [[ -z "${content// /}" ]] && continue # 空行/纯注释跳过
        mod=""; cfg=""
        read -r mod cfg <<< "$content"        # 首字段=模块名，其余=配置
        [[ -z "$mod" ]] && continue
        if ! echo "$_REGISTRY_MODULES" | grep -qw "$mod"; then
            warn "profile 引用未知模块：${mod}（已跳过）"
            continue
        fi
        p_mods+=("$mod")
        p_cfgs+=("$cfg")
    done < "$file"

    if [[ ${#p_mods[@]} -eq 0 ]]; then
        warn "profile 中没有可应用的模块：$file"
        return 0
    fi

    # 2. 拓扑排序 profile 中的模块（复用 topo_sort_all 再过滤）
    local order subset="" m found
    order=$(topo_sort_all)
    for m in $order; do
        found=false
        for mod in "${p_mods[@]}"; do [[ "$m" == "$mod" ]] && { found=true; break; }; done
        $found && subset="${subset:+$subset }$m"
    done
    [[ -z "$subset" ]] && subset="${p_mods[*]}"

    # 3. 逐个应用
    local ok=0 skipped=0 failed=0
    $dry && info "（dry-run 模式：仅预览，不实际执行）"
    for mod in $subset; do
        # 取该模块在 profile 中的配置
        cfg=""
        local i
        for i in "${!p_mods[@]}"; do
            if [[ "${p_mods[$i]}" == "$mod" ]]; then cfg="${p_cfgs[$i]}"; break; fi
        done

        local state label mod_path entry_script
        state=$(module_status_machine "$mod")
        label=$(registry_label "$mod")
        mod_path=$(registry_path "$mod")
        entry_script=$(registry_entry_script "$mod")

        # 平台可见性：profile 可跨机器携带，目标机器不适用的行跳过（不报错、不中断）
        if ! uxs_module_visible "$mod"; then
            warn "跳过 ${label}（不支持当前系统 ${OS_TYPE:-?}，仅：$(registry_platforms "$mod")）"
            skipped=$((skipped + 1))
            continue
        fi

        # 已就绪且非 --force → 跳过（n/a 视为不适用也跳过）
        if [[ "$state" != "not_installed" && "$state" != "not_configured" \
              && "$state" != "n/a" && "$force" != true ]]; then
            info "跳过 ${label}（已就绪：${state}）"
            skipped=$((skipped + 1))
            continue
        fi

        info "应用 $label ..."
        # 注入 UXS_CONFIG_<KEY>=<val>（export 到当前 shell，run_in_dir 子 shell 会继承）
        local injected=()
        if [[ -n "$cfg" ]]; then
            local kvpair k v
            for kvpair in $cfg; do
                [[ "$kvpair" != *=* ]] && continue
                k="${kvpair%%=*}"; v="${kvpair#*=}"
                if $dry; then echo "  [dry-run] 配置 UXS_CONFIG_${k}=${v}"; fi
                export "UXS_CONFIG_${k}=${v}"
                injected+=("$k")
            done
        fi

        if $dry; then
            echo "  [dry-run] 将运行：$entry_script install"
            ok=$((ok + 1))
        else
            if run_in_dir "$mod_path" "$entry_script" install; then
                ok=$((ok + 1))
            else
                error "$label 应用失败"
                failed=$((failed + 1))
            fi
        fi
        # 清理注入的环境变量，避免泄漏到后续模块
        for k in "${injected[@]+"${injected[@]}"}"; do
            unset "UXS_CONFIG_${k}"
        done
    done

    echo "----"
    success "应用完成：成功 $ok ｜ 跳过 $skipped ｜ 失败 $failed"
    [[ $failed -eq 0 ]]
}
