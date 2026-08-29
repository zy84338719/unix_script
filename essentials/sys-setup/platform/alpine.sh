#!/usr/bin/env bash
#
# essentials/sys-setup/platform/alpine.sh — Alpine

plat_mirror_preview() {
    echo "  1. 备份 /etc/apk/repositories"
    echo "  2. 重写为清华 TUNA（v$(uxs_os_release VERSION_ID) main + community）"
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
    success "Alpine 源已替换为清华镜像"
}

plat_autoupdate() {
    info "Alpine 无原生自动安全更新；建议定期执行 sudo apk upgrade"
}
