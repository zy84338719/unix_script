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

    info "$(_t 'Backing up the config...')"

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
        warn "$(_t 'No config files found to back up')"
        return 0
    fi

    # 创建备份
    if tar -czf "$backup_file" "${files_to_backup[@]}" 2>/dev/null; then
        success "$(_tf 'Config backed up to: %s' "$backup_file")"
    else
        error "$(_t 'Backup failed')"
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
        warn "$(_t 'No backup files found')"
        return 0
    fi

    printf '%s\n' "$(_t 'Available backups:')"
    for i in "${!backups[@]}"; do
        echo "  $((i+1))) $(basename "${backups[$i]}")"
    done

    read -r -p "$(_tf 'Select a backup (1-%s): ' "${#backups[@]}")" choice

    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        error "$(_t 'Invalid selection')"
        return 1
    fi

    local selected_backup="${backups[$((choice-1))]}"

    if ! yes_no "$(_tf 'Restore the config from %s?' "$(basename "$selected_backup")")"; then
        info "$(_t 'Restore cancelled')"
        return 0
    fi

    info "$(_t 'Restoring the config...')"

    # 备份当前配置
    config_backup

    # 恢复配置
    if tar -xzf "$selected_backup" -C "$HOME"; then
        success "$(_t 'Config restored')"
    else
        error "$(_t 'Restore failed')"
        return 1
    fi
}

# 导出配置
config_export() {
    ensure_config_dir

    local export_file="$CONFIG_DIR/zsh-config-export.json"

    info "$(_t 'Exporting the config...')"

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
                theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2 || true)
                config_json+=$(json_escape "$theme")
            fi
            ;;
        prezto)
            if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                local theme
                theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}' | tr -d "'" || true)
                config_json+=$(json_escape "$theme")
            fi
            ;;
    esac

    config_json+="\",
  \"export_date\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}"

    echo "$config_json" > "$export_file"

    success "$(_tf 'Config exported to: %s' "$export_file")"
}

# 导入配置
config_import() {
    local import_file="$1"

    if [ -z "$import_file" ]; then
        error "$(_t 'Please specify a file to import')"
        return 1
    fi

    if [ ! -f "$import_file" ]; then
        error "$(_tf 'File does not exist: %s' "$import_file")"
        return 1
    fi

    info "$(_t 'Importing the config...')"

    # 验证 JSON 格式
    if ! command_exists jq; then
        warn "$(_t 'jq is not installed, skipping JSON validation')"
    else
        if ! jq . "$import_file" > /dev/null 2>&1; then
            error "$(_t 'Invalid JSON format')"
            return 1
        fi
    fi

    # 备份当前配置
    config_backup

    # 导入配置（目前为占位实现，仅验证文件并备份当前配置）
    info "$(_t 'Import is a placeholder: file validated and config backed up')"
    info "$(_t 'Import is a placeholder implementation')"
    info "$(_t 'Adjust the config manually as needed')"
}
