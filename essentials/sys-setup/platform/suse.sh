#!/usr/bin/env bash
#
# essentials/sys-setup/platform/suse.sh — SUSE 族（opensuse-leap/tumbleweed/sles）

plat_mirror_preview() {
    echo "  1. $(_t 'Back up /etc/zypp/repos.d')"
    echo "  2. $(_t 'sed: replace download.opensuse.org with Tsinghua TUNA')"
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
    success "$(_t 'openSUSE source replaced by the Tsinghua mirror (repos.d backed up)')"
}

plat_autoupdate() {
    pkg_install yast2-online-update-configuration 2>/dev/null || true
    info "$(_t 'openSUSE: use yast2 online_update, or run sudo zypper patch regularly')"
}
