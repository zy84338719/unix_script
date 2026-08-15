#!/usr/bin/env bash
#
# lib/suggest.sh
#
# 纯函数工具库：编辑距离、未知模块建议、多选输入解析。
# 依赖：调用方已 source lib/registry.sh 且完成 registry_scan（仅 suggest_module 需要）。
# bash 3.2 兼容：仅用索引数组与算术展开，无关联数组/${var,,}/wait -n。
#

# 幂等保护
if [[ -n "${_SUGGEST_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_SUGGEST_SH_LOADED=1

# 两字符串的 Levenshtein 编辑距离（纯 bash DP，两行滚动数组）
levenshtein() {
    local a="$1" b="$2"
    local alen=${#a} blen=${#b}
    if [[ "$a" == "$b" ]]; then echo 0; return 0; fi
    if (( alen == 0 )); then echo "$blen"; return 0; fi
    if (( blen == 0 )); then echo "$alen"; return 0; fi
    local i j cost above left diag best
    local prev=() cur=()
    for ((j = 0; j <= blen; j++)); do prev[j]=$j; done
    for ((i = 1; i <= alen; i++)); do
        cur[0]=$i
        for ((j = 1; j <= blen; j++)); do
            if [[ "${a:i-1:1}" == "${b:j-1:1}" ]]; then cost=0; else cost=1; fi
            above=$(( prev[j] + 1 ))
            left=$(( cur[j-1] + 1 ))
            diag=$(( prev[j-1] + cost ))
            best=$above
            if (( left < best )); then best=$left; fi
            if (( diag < best )); then best=$diag; fi
            cur[j]=$best
        done
        prev=("${cur[@]}")
    done
    echo "${prev[blen]}"
}

# 未知模块名建议：前缀匹配 → 子串匹配 → 编辑距离 ≤ 2，至多 3 个
suggest_module() {
    local input="$1"
    local lower
    lower=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
    local mod lmod hits="" n
    # 1) 前缀（输入至少 2 字符，避免单字符噪声）
    if (( ${#lower} >= 2 )); then
        for mod in $_REGISTRY_MODULES; do
            lmod=$(printf '%s' "$mod" | tr '[:upper:]' '[:lower:]')
            if [[ "$lmod" == "$lower"* ]]; then
                hits="$hits $mod"
            fi
        done
    fi
    # 2) 子串
    for mod in $_REGISTRY_MODULES; do
        case " $hits " in *" $mod "*) continue ;; esac
        lmod=$(printf '%s' "$mod" | tr '[:upper:]' '[:lower:]')
        if [[ "$lmod" == *"$lower"* ]]; then
            hits="$hits $mod"
        fi
    done
    # 3) 编辑距离 ≤ 2（仅当前缀/子串均无命中时才启用，避免噪声候选）
    if [[ -z "${hits# }" ]]; then
        for mod in $_REGISTRY_MODULES; do
            n=$(printf '%s' "$hits" | wc -w)
            if (( n >= 3 )); then break; fi
            if (( $(levenshtein "$lower" "$mod") <= 2 )); then
                hits="$hits $mod"
            fi
        done
    fi
    # 截取前 3 个
    local out="" cnt=0
    for mod in $hits; do
        cnt=$((cnt + 1))
        if (( cnt > 3 )); then break; fi
        out="$out $mod"
    done
    echo "${out# }"
}

# 多选输入解析：parse_multiselect <输入> <最大序号>
#   输入形如 1 / 1,3 / 2-5 / 1,3,5-8（可混合、乱序、重复）
#   成功：输出去重升序的编号列表（空格分隔），rc 0
#   失败：无输出，rc 1（非法字符 / 越界 / 逆序区间）
parse_multiselect() {
    local input="$1" max="$2"
    [[ "$input" =~ ^[0-9] ]] || return 1
    local out="" item lo hi n
    local IFS=','
    local -a tokens
    read -ra tokens <<< "$input"
    unset IFS
    for item in "${tokens[@]}"; do
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            lo=$item; hi=$item
        elif [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            lo=${BASH_REMATCH[1]}; hi=${BASH_REMATCH[2]}
            if (( lo > hi )); then return 1; fi
        else
            return 1
        fi
        if (( lo < 1 || hi > max )); then return 1; fi
        for ((n = lo; n <= hi; n++)); do
            case " $out " in
                *" $n "*) ;;
                *) out="$out $n" ;;
            esac
        done
    done
    [[ -z "$out" ]] && return 1
    printf '%s' "${out# }" | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed 's/ $//'
}
