#!/usr/bin/env bash
#
# safe-rm/lib_trash.sh
#
# 回收站核心函数库（被 shell rc source）。
# 把删除改为"移动到回收站"，并提供查看/恢复/清空能力。
#
# 提供:
#   t / trash <文件...>            安全删除（移到回收站）
#   tls / trashlist                 查看回收站内容
#   trash-restore / restore <序号>  恢复（序号来自 tls 输出）
#   trash-empty                     清空回收站
#   trash-size                      查看回收站占用空间
#
# 回收站位置遵循 FreeDesktop 规范：~/.local/share/Trash/{files,info}
#
# 本文件需要按删除时间倒序列出回收站项，使用 ls -1t（SC2012 在此为刻意用法）。
# shellcheck disable=SC2012

# 回收站根目录（XDG_DATA_HOME 兼容）
_TRASH_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
_TRASH_FILES="$_TRASH_ROOT/files"
_TRASH_INFO="$_TRASH_ROOT/info"

# 初始化回收站目录
_trash_init() {
    mkdir -p "$_TRASH_FILES" "$_TRASH_INFO"
}

# 安全删除：t / trash <文件...>
# 兼容 rm 的 -r/-f/-- 等选项（语义都是移到回收站，不区分递归/强制）
trash() {
    _trash_init
    local args=()
    # 解析参数：忽略 rm 风格选项（-r/-R/-f/--recursive/--force 及组合如 -rf），收集文件名
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --) shift; while [[ $# -gt 0 ]]; do args+=("$1"); shift; done ;;
            -*) shift ;;
            *)  args+=("$1"); shift ;;
        esac
    done

    if [[ ${#args[@]} -eq 0 ]]; then
        echo "用法: t <文件...>   安全删除（移到回收站，可用 -r/-f 兼容 rm 习惯）" >&2
        return 1
    fi

    local item ts dest_basename dest_file dest_info err=0
    local orig_dir
    orig_dir="$PWD"
    for item in "${args[@]}"; do
        # 解析为绝对路径
        local full
        if [[ "$item" = /* ]]; then
            full="$item"
        else
            full="$orig_dir/$item"
        fi
        if [[ ! -e "$full" ]] && [[ ! -L "$full" ]]; then
            echo "trash: 无法删除 '$item'：文件不存在" >&2
            err=1
            continue
        fi
        ts=$(date +%Y%m%d_%H%M%S)
        # 回收站内的唯一文件名：原名_时间戳
        local base
        base=$(basename -- "$full")
        dest_basename="${base}_${ts}"
        dest_file="$_TRASH_FILES/$dest_basename"
        dest_info="$_TRASH_INFO/$dest_basename.trashinfo"

        # 移动文件
        if mv -f -- "$full" "$dest_file" 2>/dev/null; then
            # 写入 trashinfo（用于恢复：记录原路径与删除时间）
            {
                printf '[Trash Info]\n'
                printf 'Path=%s\n' "$full"
                printf 'DeletionDate=%s\n' "$(date +%Y-%m-%dT%H:%M:%S)"
            } > "$dest_info"
        else
            echo "trash: 删除 '$item' 失败" >&2
            err=1
        fi
    done
    return $err
}

# 查看回收站：tls / trashlist
trashlist() {
    _trash_init
    local count=0
    echo "回收站：$_TRASH_FILES"
    echo "-----------------------------------------------"
    # 按删除时间倒序（文件名含时间戳）。ls -1t 输出纯文件名，需拼接目录。
    local name f base orig
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        f="$_TRASH_FILES/$name"
        [[ -e "$f" ]] || continue
        base="$name"
        # 读取原路径
        orig=$(grep '^Path=' "$_TRASH_INFO/$name.trashinfo" 2>/dev/null | cut -d= -f2-)
        [[ -z "$orig" ]] && orig="(未知)"
        count=$((count + 1))
        printf '%2d) %-30s <- %s\n' "$count" "$base" "$orig"
    done < <(ls -1t "$_TRASH_FILES" 2>/dev/null)
    echo "-----------------------------------------------"
    if [[ $count -eq 0 ]]; then
        echo "（回收站为空）"
    else
        echo "共 $count 项。恢复请用：trash-restore <序号>"
    fi
}

# 恢复：trash-restore / restore <序号>
trash-restore() {
    _trash_init
    local idx="${1:-}"
    if [[ -z "$idx" ]]; then
        echo "用法: trash-restore <序号>   （序号来自 tls）" >&2
        return 1
    fi
    # 按同样的排序取出第 idx 个
    local name f i=0 target="" target_info orig
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        f="$_TRASH_FILES/$name"
        [[ -e "$f" ]] || continue
        i=$((i + 1))
        if [[ "$i" -eq "$idx" ]]; then
            target="$f"
            break
        fi
    done < <(ls -1t "$_TRASH_FILES" 2>/dev/null)

    if [[ -z "$target" ]]; then
        echo "trash-restore: 序号 $idx 无效" >&2
        return 1
    fi
    # trashinfo 文件位于 ${_TRASH_INFO}，文件名 = <回收站文件名>.trashinfo
    target_info="$_TRASH_INFO/$(basename -- "$target").trashinfo"
    orig=$(grep '^Path=' "$target_info" 2>/dev/null | cut -d= -f2-)
    if [[ -z "$orig" ]]; then
        echo "trash-restore: 找不到原始路径信息，无法恢复" >&2
        return 1
    fi
    # 若原路径已存在（被新文件占用），加 .restored 后缀避免覆盖
    local restore_path="$orig"
    if [[ -e "$restore_path" ]]; then
        restore_path="${orig}.restored.$(date +%s)"
        echo "注意：原路径已存在文件，恢复到：$restore_path"
    fi
    # 确保父目录存在
    mkdir -p "$(dirname -- "$restore_path")" 2>/dev/null
    if mv -f -- "$target" "$restore_path" 2>/dev/null; then
        rm -f -- "$target_info"
        echo "已恢复：$restore_path"
    else
        echo "trash-restore: 恢复失败" >&2
        return 1
    fi
}

# 清空回收站：trash-empty [--force|-f]
# 默认需 --force 确认（避免跨 shell 的 read 交互差异，且更脚本友好）
trash-empty() {
    _trash_init
    local force=false
    [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]] && force=true
    local c
    c=$(find "$_TRASH_FILES" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$c" -eq 0 ]]; then
        echo "回收站已是空的。"
        return 0
    fi
    if [[ "$force" != true ]]; then
        echo "回收站有 $c 项。确认清空请用：trash-empty --force"
        trash-size
        return 0
    fi
    rm -rf "${_TRASH_FILES:?}/"* "${_TRASH_INFO:?}/"* 2>/dev/null || true
    echo "回收站已清空。"
}

# 查看回收站占用空间：trash-size
trash-size() {
    _trash_init
    echo "回收站占用："
    du -sh "$_TRASH_FILES" 2>/dev/null | cut -f1 | sed 's/^/  /'
}

# 别名（短命令）
alias t='trash'
alias tls='trashlist'
alias restore='trash-restore'
