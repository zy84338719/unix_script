#!/bin/bash
#
# zsh_setup/lib/config.sh
# 配置管理模块
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 确保配置目录存在
ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
}

# 备份配置
config_backup() {
    ensure_config_dir

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/zsh-backup-$timestamp.tar.gz"

    info "正在备份配置..."

    # 收集配置文件
    local files_to_backup=()

    # .zshrc
    [ -f "$HOME/.zshrc" ] && files_to_backup+=("$HOME/.zshrc")

    # Oh My Zsh
    [ -d "$HOME/.oh-my-zsh/custom" ] && files_to_backup+=("$HOME/.oh-my-zsh/custom")

    # Prezto
    [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ] && files_to_backup+=("${ZDOTDIR:-$HOME}/.zpreztorc")

    # sheldon
    [ -f "$HOME/.config/sheldon/plugins.toml" ] && files_to_backup+=("$HOME/.config/sheldon/plugins.toml")

    # Powerlevel10k 配置
    [ -f "$HOME/.p10k.zsh" ] && files_to_backup+=("$HOME/.p10k.zsh")

    if [ ${#files_to_backup[@]} -eq 0 ]; then
        warn "没有找到需要备份的配置文件"
        return 0
    fi

    # 创建备份
    if tar -czf "$backup_file" "${files_to_backup[@]}" 2>/dev/null; then
        success "配置已备份到: $backup_file"
    else
        error "备份失败"
        return 1
    fi
}

# 恢复配置
config_restore() {
    ensure_config_dir

    # 列出可用备份
    local backups=("$BACKUP_DIR"/zsh-backup-*.tar.gz)

    # bash 3.2 does not expand globs when no files match; check for actual file
    if [ ! -f "${backups[0]}" ]; then
        warn "没有找到备份文件"
        return 0
    fi

    echo "可用备份:"
    for i in "${!backups[@]}"; do
        echo "  $((i+1))) $(basename "${backups[$i]}")"
    done

    read -r -p "请选择备份 (1-${#backups[@]}): " choice

    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        error "无效选择"
        return 1
    fi

    local selected_backup="${backups[$((choice-1))]}"

    if ! yes_no "确定要从 $(basename "$selected_backup") 恢复配置吗？"; then
        info "取消恢复"
        return 0
    fi

    info "正在恢复配置..."

    # 备份当前配置
    config_backup

    # 恢复配置
    if tar -xzf "$selected_backup" -C "$HOME"; then
        success "配置已恢复"
    else
        error "恢复失败"
        return 1
    fi
}

# 导出配置
config_export() {
    ensure_config_dir

    local export_file="$CONFIG_DIR/zsh-config-export.json"

    info "正在导出配置..."

    local framework
    framework=$(detect_framework)

    # 收集配置信息
    local esc_framework
    esc_framework=$(json_escape "$framework")
    local config_json="{
  \"framework\": \"${esc_framework}\",
  \"plugins\": ["

    # 收集插件列表
    case "$framework" in
        oh-my-zsh)
            if [ -d "$HOME/.oh-my-zsh/custom/plugins" ]; then
                local plugins=()
                for plugin in "$HOME/.oh-my-zsh/custom/plugins/"*/; do
                    [ -d "$plugin" ] && plugins+=("\"$(json_escape "$(basename "$plugin")")\"")
                done
                config_json+=$(IFS=,; echo "${plugins[*]}")
            fi
            ;;
        zinit)
            if [ -f "$HOME/.zshrc" ]; then
                local plugins=()
                while IFS= read -r line; do
                    local plugin
                    plugin=$(echo "$line" | sed 's/.*zinit light //' | sed 's/["]//g')
                    [ -n "$plugin" ] && plugins+=("\"$(json_escape "$plugin")\"")
                done < <(grep "zinit light" "$HOME/.zshrc" 2>/dev/null)
                config_json+=$(IFS=,; echo "${plugins[*]}")
            fi
            ;;
    esac

    config_json+="],
  \"theme\": \""

    # 收集主题
    case "$framework" in
        oh-my-zsh)
            if [ -f "$HOME/.zshrc" ]; then
                local theme
                theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2)
                config_json+=$(json_escape "$theme")
            fi
            ;;
        prezto)
            if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                local theme
                theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}' | tr -d "'")
                config_json+=$(json_escape "$theme")
            fi
            ;;
    esac

    config_json+="\",
  \"export_date\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}"

    echo "$config_json" > "$export_file"

    success "配置已导出到: $export_file"
}

# 导入配置
config_import() {
    local import_file="$1"

    if [ -z "$import_file" ]; then
        error "请指定导入文件"
        return 1
    fi

    if [ ! -f "$import_file" ]; then
        error "文件不存在: $import_file"
        return 1
    fi

    info "正在导入配置..."

    # 验证 JSON 格式
    if ! command_exists jq; then
        warn "未安装 jq，跳过 JSON 验证"
    else
        if ! jq . "$import_file" > /dev/null 2>&1; then
            error "无效的 JSON 格式"
            return 1
        fi
    fi

    # 备份当前配置
    config_backup

    # 导入配置（目前为占位实现，仅验证文件并备份当前配置）
    info "导入功能暂为占位实现，已完成文件验证和当前配置备份"
    info "导入功能暂为占位实现"
    info "请根据需要手动调整配置"
}
