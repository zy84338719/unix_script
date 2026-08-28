#!/usr/bin/env bash
#
# essentials/sys-setup/platform/debian.sh
#
# Debian 族（DISTRO_FAMILY=debian）平台实现。
# 覆盖 DISTRO_ID：ubuntu / linuxmint / debian / deepin / uos；
# kylin(桌面) / openkylin 无公开镜像，降级指引。
# 只含「名词」：模板、路径、清单；动词（pkg_install / uxs_svc）来自 lib。

MIRROR_BASE="https://mirrors.tuna.tsinghua.edu.cn"

# 停用除主文件外仍指向发行版归档的 apt 源文件（deb822 与一行式都查），
# 避免新旧源并存：索引重复下载、security 残留官方源、modernize-sources 提示。
# 停用方式 = 重命名为 *.bak.<ts>（apt 只读 .list/.sources 后缀，随时可改回）。
_apt_disable_distro_sources() {
    local primary="$1" ts="$2" f
    # 匹配发行版归档 URI：官方 archive/security/deb.debian.org + 各国内镜像站的 ubuntu/debian 路径
    local pattern='(archive|security|azure|cn)\.ubuntu\.com|(deb|security)\.debian\.org|mirrors\.[A-Za-z.]+/(ubuntu|debian)'
    local -a candidates=(/etc/apt/sources.list)
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$f" ]] && candidates+=("$f")
    done
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$primary" ]] && continue
        if sudo grep -Eq "$pattern" "$f" 2>/dev/null; then
            sudo mv "$f" "${f}.bak.$ts" 2>/dev/null || { warn "停用失败（权限？）：$f"; continue; }
            warn "已停用重复/残留源文件：$f（恢复：sudo mv ${f}.bak.$ts $f）"
        fi
    done
}

# apt 主源文件：deb822 优先（Ubuntu 24.04+/Debian 13 起发行版源在
# sources.list.d/*.sources），只重写 sources.list 会与之并存导致索引重复、
# security 残留官方源；无 deb822 文件则回退传统 sources.list。
_deb_primary_target() {
    case "$DISTRO_ID" in
        ubuntu|linuxmint)
            if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
                echo /etc/apt/sources.list.d/ubuntu.sources; return
            fi
            ;;
        debian)
            if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
                echo /etc/apt/sources.list.d/debian.sources; return
            fi
            ;;
    esac
    echo /etc/apt/sources.list
}

plat_mirror_preview() {
    local codename primary
    case "$DISTRO_ID" in
        ubuntu|linuxmint|debian)
            codename=$(uxs_os_release VERSION_CODENAME)
            primary=$(_deb_primary_target)
            echo "  1. 备份并重写 ${primary} 为清华 TUNA（${DISTRO_ID}/${codename:-?}）"
            echo "  2. 停用其余发行版归档 apt 源（重命名 *.bak.<ts>，可随时恢复）"
            echo "  3. sudo apt-get update"
            ;;
        deepin|uos)
            codename=$(uxs_os_release VERSION_CODENAME)
            echo "  1. 备份并重写 /etc/apt/sources.list 为清华 TUNA（${DISTRO_ID}/${codename:-?}，main community）"
            echo "  2. 停用其余发行版归档 apt 源"
            echo "  3. sudo apt-get update"
            ;;
        *)
            echo "  1. ${DISTRO_ID} 暂无公开镜像仓库，仅打印指引（不改动系统）"
            ;;
    esac
}

plat_mirror_apply() {
    local codename ts primary
    codename=$(uxs_os_release VERSION_CODENAME)
    ts=$(date +%s)
    case "$DISTRO_ID" in
        ubuntu|linuxmint|debian)
            if [[ -z "$codename" ]]; then
                error "无法识别发行版代号（VERSION_CODENAME）"
                return 1
            fi
            primary=$(_deb_primary_target)
            sudo cp -a "$primary" "${primary}.bak.$ts" 2>/dev/null || true
            if [[ "$primary" == *.sources ]]; then
                if [[ "$DISTRO_ID" == "debian" ]]; then
                    sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 ${primary}.bak.$ts）
Types: deb
URIs: ${MIRROR_BASE}/debian/
Suites: ${codename} ${codename}-updates ${codename}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${MIRROR_BASE}/debian-security/
Suites: ${codename}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
                else
                    sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 ${primary}.bak.$ts）
Types: deb
URIs: ${MIRROR_BASE}/ubuntu/
Suites: ${codename} ${codename}-updates ${codename}-backports ${codename}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
                fi
            elif [[ "$DISTRO_ID" == "debian" ]]; then
                sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 .bak.*）
deb ${MIRROR_BASE}/debian/ ${codename} main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian/ ${codename}-backports main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
            else
                sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 .bak.*）
deb ${MIRROR_BASE}/ubuntu/ ${codename} main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-updates main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-backports main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-security main restricted universe multiverse
EOF
            fi
            _apt_disable_distro_sources "$primary" "$ts"
            success "apt 源已更换为清华镜像（${DISTRO_ID}/${codename}），原文件已备份"
            sudo apt-get update
            ;;
        deepin|uos)
            # TUNA /deepin/ 仓库实测可用；components 与 Ubuntu 不同（main community）
            if [[ -z "$codename" ]]; then
                error "无法识别发行版代号（VERSION_CODENAME）"
                return 1
            fi
            primary=/etc/apt/sources.list
            sudo cp -a "$primary" "${primary}.bak.$ts" 2>/dev/null || true
            sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 ${primary}.bak.$ts）
deb ${MIRROR_BASE}/deepin/ ${codename} main community
EOF
            _apt_disable_distro_sources "$primary" "$ts"
            success "apt 源已更换为清华镜像（${DISTRO_ID}/${codename}）"
            sudo apt-get update
            ;;
        *)
            warn "银河麒麟/openKylin 暂无公开镜像仓库，保持系统源不变"
            warn "如需换源请使用系统自带「软件源」工具或参考服务器版官方文档"
            ;;
    esac
}

plat_autoupdate() {
    case "$DISTRO_ID" in
        deepin|uos)
            warn "${DISTRO_ID} 的自动安全更新由系统更新器管理，跳过"
            ;;
        *)
            pkg_install unattended-upgrades apt-listchanges
            sudo dpkg-reconfigure -fnoninteractive -plow unattended-upgrades 2>/dev/null || true
            success "已启用 Debian/Ubuntu/Mint 自动安全更新（unattended-upgrades）"
            ;;
    esac
}
