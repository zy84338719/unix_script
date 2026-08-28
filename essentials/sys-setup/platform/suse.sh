#!/usr/bin/env bash
#
# essentials/sys-setup/platform/suse.sh — SUSE 族（opensuse-leap/tumbleweed/sles）

plat_mirror_preview() {
    echo "  1. 备份 /etc/zypp/repos.d"
    echo "  2. sed 将 download.opensuse.org 替换为清华 TUNA（保留原 repo 结构）"
    echo "  3. sudo zypper --non-interactive refresh"
}

plat_mirror_apply() {
    local ts
    ts=$(date +%s)
    sudo cp -a /etc/zypp/repos.d "/etc/zypp/repos.d.bak.$ts" 2>/dev/null || true
    sudo sed -i.bak \
        -e 's|download.opensuse.org|mirrors.tuna.tsinghua.edu.cn/opensuse|g' \
        -e 's|download.tumbleweed|mirrors.tuna.tsinghua.edu.cn/opensuse/tumbleweed|g' \
        /etc/zypp/repos.d/*.repo 2>/dev/null || true
    sudo zypper --non-interactive refresh 2>/dev/null || true
    success "openSUSE 源已替换为清华镜像（原 /etc/zypp/repos.d 已备份）"
}

plat_autoupdate() {
    pkg_install yast2-online-update-configuration 2>/dev/null || true
    info "openSUSE 建议用 yast2 online_update 配置自动补丁；或定期执行 sudo zypper patch"
}
