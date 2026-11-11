#!/usr/bin/env bash
#
# essentials/sys-setup/platform/alpine.sh — Alpine

plat_mirror_preview() {
    local ver
    ver=$(uxs_os_release VERSION_ID)
    echo "  1. $(_t 'Back up /etc/apk/repositories')"
    echo "  2. $(_tf 'Rewrite to Tsinghua TUNA (v%s main + community)' "$ver")"
    echo "  3. sudo apk update"
}

plat_mirror_apply() {
    local ver ts
    ver=$(uxs_os_release VERSION_ID)
    [[ -z "$ver" ]] && ver="latest-stable"
    ts=$(date +%s)
    sudo cp -a /etc/apk/repositories "/etc/apk/repositories.bak.$ts" 2>/dev/null || true
    sudo tee /etc/apk/repositories >/dev/null <<EOF
# 由 unix_script sys-setup 生成 —— Alpine 清华镜像
https://mirrors.tuna.tsinghua.edu.cn/alpine/v${ver}/main
https://mirrors.tuna.tsinghua.edu.cn/alpine/v${ver}/community
EOF
    sudo apk update 2>/dev/null || true
    success "$(_t 'The Alpine source has been replaced by the Tsinghua mirror')"
}

plat_autoupdate() {
    info "$(_t 'No native automatic security updates in Alpine, run sudo apk upgrade')"
}
