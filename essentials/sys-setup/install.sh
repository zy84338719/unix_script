#!/usr/bin/env bash
#
# sys-setup/install.sh
#
# 装机必设置：系统初始化配置集合。仅 Linux。
# 每个子命令对应一项常用装机配置：
#
#   mirror      —— 更换系统软件源为国内镜像（Debian/Ubuntu/CentOS）
#   timezone    —— 设置时区并启用 NTP 时间同步
#   optimize    —— 系统参数优化（文件描述符、TCP、内核）
#   ssh         —— SSH 加固（禁用密码登录、禁用 root 直登）
#   autoupdate  —— 启用自动安全更新（unattended-upgrades）
#   all         —— 依次执行以上全部
#   status      —— 查看各项配置状态
#   help        —— 帮助
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "sys-setup 仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
    require_sudo
}

# -------- 1. 换源（国内镜像） --------
# 国内镜像源（清华 TUNA）
MIRROR_BASE="https://mirrors.tuna.tsinghua.edu.cn"

do_mirror() {
    preflight
    detect_pkg_manager
    info "🌐 更换软件源为国内镜像（清华 TUNA）"

    # 识别发行版（优先用 os-release 的 ID，回退到文件检测）
    local os_id=""
    os_id=$(. /etc/os-release 2>/dev/null && echo "$ID")
    local distro=""
    case "$os_id" in
        ubuntu|linuxmint) distro="ubuntu" ;;   # Mint 基于 Ubuntu，apt 源结构相同
        debian)           distro="debian" ;;
        centos)           distro="centos" ;;
        almalinux|rocky|rhel|fedora) distro="rhel" ;;  # AlmaLinux/Rocky/RHEL/Fedora: dnf 系
        opensuse-leap|opensuse-tumbleweed|sles|suse) distro="opensuse" ;;
        arch|manjaro|garuda) distro="arch" ;;
        alpine)           distro="alpine" ;;
        *)
            # 回退：按文件特征判断
            if [[ -f /etc/debian_version ]]; then
                distro="debian"
                grep -q '^ID=ubuntu' /etc/os-release 2>/dev/null && distro="ubuntu"
            elif [[ -f /etc/centos-release ]] || [[ -f /etc/redhat-release ]]; then
                distro="centos"
            fi
            ;;
    esac

    case "$distro" in
        debian|ubuntu)
            local codename
            codename=$(. /etc/os-release 2>/dev/null && echo "$VERSION_CODENAME")
            if [[ -z "$codename" ]]; then
                error "无法识别发行版代号（VERSION_CODENAME）"
                return 1
            fi
            sudo cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%s)" 2>/dev/null || true
            if [[ "$distro" == "ubuntu" ]]; then
                sudo tee /etc/apt/sources.list >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 .bak.*）
deb ${MIRROR_BASE}/ubuntu/ ${codename} main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-updates main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-backports main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-security main restricted universe multiverse
EOF
            else
                sudo tee /etc/apt/sources.list >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 .bak.*）
deb ${MIRROR_BASE}/debian/ ${codename} main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian/ ${codename}-backports main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
            fi
            success "apt 源已更换为清华镜像（$distro/$codename），原文件已备份"
            sudo apt-get update
            ;;
        centos|rhel)
            # 通过 os-release 区分 CentOS Stream 9 / 其他版本或衍生版
            local os_id os_ver is_stream
            os_id=$(. /etc/os-release 2>/dev/null && echo "$ID")
            os_ver=$(. /etc/os-release 2>/dev/null && echo "$VERSION_ID")
            is_stream=$(. /etc/os-release 2>/dev/null && echo "$NAME" | grep -qi stream && echo yes || echo no)

            # 备份现有 repo 文件
            local ts; ts=$(date +%s)
            sudo cp -a /etc/yum.repos.d "/etc/yum.repos.d.bak.$ts" 2>/dev/null || true

            if [[ "$is_stream" == "yes" ]] && [[ "$os_ver" == 9* ]]; then
                # CentOS Stream 9：覆盖 centos.repo（核心仓库指向清华镜像）
                info "检测到 CentOS Stream $os_ver，覆盖 centos.repo 为清华镜像"
                sudo tee /etc/yum.repos.d/centos.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— CentOS Stream 9 清华 TUNA 镜像
[baseos]
name=CentOS Stream $releasever - BaseOS
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/$releasever-stream/BaseOS/$basearch/os
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
gpgcheck=1
enabled=1

[appstream]
name=CentOS Stream $releasever - AppStream
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/$releasever-stream/AppStream/$basearch/os
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
gpgcheck=1
enabled=1

[crb]
name=CentOS Stream $releasever - CRB
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/$releasever-stream/CRB/$basearch/os
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
gpgcheck=1
enabled=1

[extras-common]
name=CentOS Stream $releasever - Extras packages
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/SIGs/$releasever-stream/extras/$basearch/extras-common
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Extras-SHA512
gpgcheck=1
enabled=1
EOF
                success "CentOS Stream 9 源已更换为清华镜像（原 /etc/yum.repos.d 已备份）"
                sudo dnf clean all 2>/dev/null || true
                sudo dnf makecache 2>/dev/null || true
            else
                # CentOS 7/8 等老版或 AlmaLinux/Rocky Linux 等衍生版
                info "检测到 RHEL 系发行版：$os_id $os_ver（非 Stream 9）"
                info "衍生版/老版换源请参考对应镜像帮助："
                echo "  CentOS 7:   https://mirrors.tuna.tsinghua.edu.cn/help/centos-vault/"
                echo "  AlmaLinux:  https://mirrors.tuna.tsinghua.edu.cn/help/almalinux/"
                echo "  Rocky:      https://mirrors.tuna.tsinghua.edu.cn/help/rocky/"
                warn "已备份原 /etc/yum.repos.d 到 .bak.$ts，请按指引手动替换 baseurl"
            fi
            ;;
        opensuse)
            # openSUSE：替换 zypper 仓库 URL 为清华镜像
            local ts; ts=$(date +%s)
            sudo cp -a /etc/zypp/repos.d "/etc/zypp/repos.d.bak.$ts" 2>/dev/null || true
            info "openSUSE 换源：将所有仓库 URL 替换为清华镜像"
            sudo sed -i.bak \
                -e 's|download.opensuse.org|mirrors.tuna.tsinghua.edu.cn/opensuse|g' \
                -e 's|download.tumbleweed|mirrors.tuna.tsinghua.edu.cn/opensuse/tumbleweed|g' \
                /etc/zypp/repos.d/*.repo 2>/dev/null || true
            sudo zypper --non-interactive refresh 2>/dev/null || true
            success "openSUSE 源已替换为清华镜像（原 /etc/zypp/repos.d 已备份）"
            ;;
        arch)
            # Arch：替换 mirrorlist 为清华镜像（启用 Server 行）
            info "Arch Linux 换源：生成清华镜像 /etc/pacman.d/mirrorlist"
            local ts; ts=$(date +%s)
            sudo cp -a /etc/pacman.d/mirrorlist "/etc/pacman.d/mirrorlist.bak.$ts" 2>/dev/null || true
            sudo tee /etc/pacman.d/mirrorlist >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— Arch Linux 清华镜像
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
EOF
            sudo pacman -Sy 2>/dev/null || true
            success "Arch mirrorlist 已替换为清华镜像"
            ;;
        alpine)
            # Alpine：替换 /etc/apk/repositories 为清华镜像
            local alpine_ver
            alpine_ver=$(. /etc/os-release 2>/dev/null && echo "$VERSION_ID")
            [[ -z "$alpine_ver" ]] && alpine_ver="latest-stable"
            local ts; ts=$(date +%s)
            sudo cp -a /etc/apk/repositories "/etc/apk/repositories.bak.$ts" 2>/dev/null || true
            sudo tee /etc/apk/repositories >/dev/null <<EOF
# 由 unix_script sys-setup 生成 —— Alpine 清华镜像
https://mirrors.tuna.tsinghua.edu.cn/alpine/v${alpine_ver}/main
https://mirrors.tuna.tsinghua.edu.cn/alpine/v${alpine_ver}/community
EOF
            sudo apk update 2>/dev/null || true
            success "Alpine 源已替换为清华镜像"
            ;;
        *)
            warn "无法识别发行版，跳过换源。当前支持 Debian/Ubuntu/Mint/CentOS/AlmaLinux/Rocky/openSUSE/Arch/Alpine。"
            ;;
    esac
}

# -------- 2. 时区 + 时间同步 --------
# 预设 NTP 服务器
NTP_PRESET_ALIYUN="ntp.aliyun.com ntp1.aliyun.com ntp2.aliyun.com"
NTP_PRESET_TUNA="ntp.tuna.tsinghua.edu.cn"
NTP_PRESET_NTPPOOL="0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org"
NTP_PRESET_CSTTIME="cn.ntp.org.cn"
NTP_PRESET_GOOGLE="time1.google.com time2.google.com"
NTP_PRESET_HUAWEI="ntp.huaweicloud.com"

# 配置 systemd-timesyncd 的 NTP 服务器
_configure_timesyncd() {
    local servers="$1"
    local conf="/etc/systemd/timesyncd.conf"
    sudo mkdir -p /etc/systemd

    # 备份原配置
    if [[ -f "$conf" ]]; then
        sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true
    fi

    # 构建 NTP= 行（空格分隔）
    local ntp_line
    ntp_line=$(echo "$servers" | tr ' ' '\n' | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//')

    # 写入配置（保留其他设置，只更新 [Time] 段的 NTP 和 FallbackNTP）
    if [[ -f "$conf" ]] && grep -q '^\[Time\]' "$conf" 2>/dev/null; then
        # 已有 [Time] 段：替换或追加 NTP=
        if grep -q '^NTP=' "$conf"; then
            sudo sed -i "s|^NTP=.*|NTP=${ntp_line}|" "$conf"
        else
            sudo sed -i "/^\[Time\]/a NTP=${ntp_line}" "$conf"
        fi
    else
        # 没有 [Time] 段：追加
        {
            echo ""
            echo "[Time]"
            echo "NTP=${ntp_line}"
        } | sudo tee -a "$conf" >/dev/null
    fi

    # 重启 timesyncd 使配置生效
    sudo systemctl restart systemd-timesyncd 2>/dev/null || true
}

# 配置 chrony 的 NTP 服务器
_configure_chrony() {
    local servers="$1"
    local conf=""
    for conf in /etc/chrony/chrony.conf /etc/chrony.conf; do
        [[ -f "$conf" ]] && break
    done
    [[ -f "$conf" ]] || { warn "未找到 chrony 配置文件"; return 1; }

    sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true

    # 注释掉原有的 server/pool 行（含缩进）
    sudo sed -i 's/^\([[:space:]]*\(server\|pool\)\) /# &/' "$conf"

    # 追加新的 server 行
    local s
    for s in $servers; do
        echo "server $s iburst" | sudo tee -a "$conf" >/dev/null
    done

    sudo systemctl restart chrony 2>/dev/null || sudo systemctl restart chronyd 2>/dev/null || true
}

# 配置 ntpd 的 NTP 服务器
_configure_ntpd() {
    local servers="$1"
    local conf="/etc/ntp.conf"
    [[ -f "$conf" ]] || { warn "未找到 ntp.conf"; return 1; }

    sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true

    # 注释掉原有的 server 行（含缩进）
    sudo sed -i 's/^\([[:space:]]*server\) /# &/' "$conf"

    # 追加新的 server 行
    local s
    for s in $servers; do
        echo "server $s iburst" | sudo tee -a "$conf" >/dev/null
    done

    sudo systemctl restart ntpd 2>/dev/null || true
}

# 设置 NTP 服务器（自动检测后端）
set_ntp_servers() {
    local servers="$1"

    # 检测使用哪个 NTP 后端
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null || \
       systemctl list-unit-files 2>/dev/null | grep -q systemd-timesyncd; then
        if _configure_timesyncd "$servers"; then
            success "已配置 systemd-timesyncd: $servers"
        else
            error "配置 systemd-timesyncd 失败"; return 1
        fi
    elif systemctl is-active --quiet chrony 2>/dev/null || \
         systemctl is-active --quiet chronyd 2>/dev/null || \
         command_exists chronyc; then
        if _configure_chrony "$servers"; then
            success "已配置 chrony: $servers"
        else
            error "配置 chrony 失败"; return 1
        fi
    elif systemctl is-active --quiet ntpd 2>/dev/null || \
         command_exists ntpd; then
        if _configure_ntpd "$servers"; then
            success "已配置 ntpd: $servers"
        else
            error "配置 ntpd 失败"; return 1
        fi
    else
        # 没有 NTP 服务，尝试安装
        warn "未检测到 NTP 服务，尝试安装..."
        detect_pkg_manager
        local install_ok=false
        case "$PKG_MANAGER" in
            apt-get) sudo apt-get install -y chrony && sudo systemctl enable --now chrony && install_ok=true ;;
            dnf)     sudo dnf install -y chrony && sudo systemctl enable --now chronyd && install_ok=true ;;
            yum)     sudo yum install -y chrony && sudo systemctl enable --now chronyd && install_ok=true ;;
            *)       warn "无法自动安装 NTP 服务（不支持的包管理器）"; return 1 ;;
        esac
        if $install_ok && command_exists chronyc; then
            _configure_chrony "$servers"
            success "已安装 chrony 并配置: $servers"
        else
            error "chrony 安装失败，请手动安装: sudo apt-get install chrony"
            return 1
        fi
    fi
}

# 查看当前 NTP 状态
show_ntp_status() {
    echo "当前 NTP 状态："
    if command_exists timedatectl; then
        timedatectl status 2>/dev/null | grep -E 'Local time|Time zone|NTP|synchronized' | sed 's/^/  /'
    fi
    # 显示实际使用的 NTP 服务器
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        echo "  后端: systemd-timesyncd"
        local conf="/etc/systemd/timesyncd.conf"
        if [[ -f "$conf" ]] && grep -q '^NTP=' "$conf"; then
            echo "  配置: $(grep '^NTP=' "$conf")"
        else
            echo "  配置: (默认)"
        fi
    elif command_exists chronyc 2>/dev/null; then
        echo "  后端: chrony"
        chronyc sources 2>/dev/null | head -8 | sed 's/^/  /'
    elif command_exists ntpq 2>/dev/null; then
        echo "  后端: ntpd"
        ntpq -p 2>/dev/null | head -8 | sed 's/^/  /'
    else
        echo "  (未检测到 NTP 服务)"
    fi
}

# NTP 交互式设置
do_ntp() {
    preflight
    info "🕐 配置 NTP 时间同步服务器"
    echo

    show_ntp_status
    echo

    menu "请选择 NTP 服务器方案："
    echo "  1) 阿里云     ($NTP_PRESET_ALIYUN)"
    echo "  2) 清华 TUNA  ($NTP_PRESET_TUNA)"
    echo "  3) 华为云     ($NTP_PRESET_HUAWEI)"
    echo "  4) 中国 NTP   ($NTP_PRESET_CSTTIME)"
    echo "  5) NTP Pool   ($NTP_PRESET_NTPPOOL)"
    echo "  6) Google     ($NTP_PRESET_GOOGLE)"
    echo "  7) 自定义（手动输入 NTP 服务器地址）"
    echo "  0) 取消"
    echo "========================================"

    local choice
    read -r -p "请输入选项 [0-7]: " choice

    local servers=""
    case "$choice" in
        1) servers="$NTP_PRESET_ALIYUN" ;;
        2) servers="$NTP_PRESET_TUNA" ;;
        3) servers="$NTP_PRESET_HUAWEI" ;;
        4) servers="$NTP_PRESET_CSTTIME" ;;
        5) servers="$NTP_PRESET_NTPPOOL" ;;
        6) servers="$NTP_PRESET_GOOGLE" ;;
        7)
            echo
            info "请输入 NTP 服务器地址（多个用空格分隔）："
            info "示例: ntp.aliyun.com ntp1.aliyun.com"
            read -r -p "> " servers
            # 去除首尾空白
            servers=$(echo "$servers" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -z "$servers" ]]; then
                warn "未输入任何服务器，已取消"
                return 0
            fi
            # 基本校验：每个词应像合法主机名（含字母/数字/点/连字符）
            local word
            for word in $servers; do
                if [[ ! "$word" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
                    error "无效的服务器地址: $word"
                    info "地址应只包含字母、数字、点、连字符，例如: ntp.aliyun.com"
                    return 1
                fi
            done
            ;;
        0|*) info "已取消"; return 0 ;;
    esac

    echo
    info "即将配置 NTP 服务器: $servers"
    if ! yes_no "确认继续？"; then
        info "已取消"; return 0
    fi

    set_ntp_servers "$servers"

    echo
    show_ntp_status
}

# 设置时区（支持参数，默认 Asia/Shanghai）
# shellcheck disable=SC2120  # 函数签名预留参数，当前未使用
do_timezone() {
    preflight
    local tz="${1:-Asia/Shanghai}"
    info "🕐 设置时区为 $tz 并启用时间同步"

    if command_exists timedatectl; then
        sudo timedatectl set-timezone "$tz"
        success "时区已设置为 $tz"
        # 优先启用 systemd-timesyncd
        if systemctl list-unit-files 2>/dev/null | grep -q systemd-timesyncd; then
            sudo systemctl enable --now systemd-timesyncd 2>/dev/null || true
            sudo timedatectl set-ntp true 2>/dev/null || true
            success "已启用 systemd-timesyncd (NTP)"
        fi
    else
        sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        success "时区已设置为 $tz（符号链接）"
    fi

    # 没有 timesyncd 时回退装 chrony/ntp
    if ! systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        detect_pkg_manager
        case "$PKG_MANAGER" in
            apt-get) sudo apt-get install -y chrony && sudo systemctl enable --now chrony ;;
            dnf)     sudo dnf install -y chrony && sudo systemctl enable --now chronyd ;;
            yum)     sudo yum install -y ntp && sudo systemctl enable --now ntpd ;;
        esac 2>/dev/null || true
        success "已安装并启用时间同步服务"
    fi
}

# -------- 3. 系统参数优化 --------
do_optimize() {
    preflight
    info "⚙️  优化系统参数（文件描述符、内核）"

    # 文件描述符上限
    local limits_file=/etc/security/limits.d/99-unix-script.conf
    sudo tee "$limits_file" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— 提升文件描述符上限
*               soft    nofile          65536
*               hard    nofile          65536
root            soft    nofile          65536
root            hard    nofile          65536
EOF
    success "已提升文件描述符上限到 65536（$limits_file）"

    # 内核参数（网络/内存）
    local sysctl_file=/etc/sysctl.d/99-unix-script.conf
    sudo tee "$sysctl_file" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— 内核参数优化
# TCP 快速回收与复用
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
# TCP keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
# 防 SYN flood
net.ipv4.tcp_syncookies = 1
# 内存
vm.swappiness = 10
vm.overcommit_memory = 1
EOF
    sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
    success "已写入内核优化参数（$sysctl_file）"
}

# -------- 4. SSH 加固 --------
do_ssh() {
    preflight
    info "🔐 SSH 加固（禁用密码登录、禁用 root 直登）"

    local sshd_config
    for sshd_config in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/99-unix-script.conf; do
        if [[ -f "$sshd_config" ]]; then break; fi
    done
    # 优先用 sshd_config.d drop-in（更干净）
    local dropin=/etc/ssh/sshd_config.d/99-unix-script.conf
    sudo mkdir -p /etc/ssh/sshd_config.d

    warn "SSH 加固是敏感操作：将禁用密码登录与 root 直登。"
    warn "请确保你已配置好 SSH 密钥登录，否则可能无法登录服务器！"
    if ! yes_no "确认继续（仅当你已配置好密钥登录）？"; then
        info "已跳过 SSH 加固"; return 0
    fi

    sudo tee "$dropin" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— SSH 加固
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
    success "已写入 SSH 加固配置（$dropin）"

    if command_exists systemctl; then
        sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null || true
        success "sshd 已 reload（配置在新连接生效）"
    fi
}

# -------- 5. 自动安全更新 --------
do_autoupdate() {
    preflight
    info "🛡️  启用自动安全更新"
    detect_pkg_manager
    case "$PKG_MANAGER" in
        apt-get)
            pkg_install unattended-upgrades apt-listchanges
            sudo dpkg-reconfigure -fnoninteractive -plow unattended-upgrades 2>/dev/null || true
            success "已启用 Debian/Ubuntu/Mint 自动安全更新（unattended-upgrades）"
            ;;
        dnf)
            pkg_install dnf-automatic
            sudo sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null || true
            sudo systemctl enable --now dnf-automatic.timer 2>/dev/null || true
            success "已启用 dnf-automatic"
            ;;
        yum)
            pkg_install yum-cron
            sudo systemctl enable --now yum-cron 2>/dev/null || true
            success "已启用 yum-cron"
            ;;
        zypper)
            # openSUSE 用 zypper-updates-service（或 yast2-online-update）
            pkg_install yast2-online-update-configuration 2>/dev/null || true
            info "openSUSE 建议用 yast2 online_update 配置自动补丁；或定期执行 sudo zypper patch"
            ;;
        pacman)
            # Arch 滚动发布，官方推荐定期 pacman -Syu；可装 pacman-contrib 的 checkupdates
            pkg_install pacman-contrib 2>/dev/null || true
            info "Arch 为滚动发布，建议定期执行 sudo pacman -Syu 保持更新"
            ;;
        apk)
            info "Alpine 无原生自动安全更新；建议定期执行 sudo apk upgrade"
            ;;
        *)
            warn "无法识别包管理器，跳过自动更新配置"
            ;;
    esac
}

# -------- 全部执行 --------
do_all() {
    info "🚀 执行全部装机必设置"
    do_mirror
    echo
    do_timezone
    echo
    do_optimize
    echo
    do_autoupdate
    echo
    do_ssh
    echo
    success "🎉 全部装机必设置执行完成"
}

# -------- 状态 --------
status_sys_setup() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        echo -e "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    echo "软件源镜像:"
    if grep -q "tuna.tsinghua\|mirrors.aliyun\|mirrors.ustc" /etc/apt/sources.list 2>/dev/null; then
        echo -e "  ${GREEN}✅ 已换国内源${NC}"
    else
        echo -e "  ${YELLOW}⚠️  默认源${NC}"
    fi
    echo "时区: $(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo '未知')"
    echo "NTP 同步: $(timedatectl show -p NTP --value 2>/dev/null || echo '未知')"
    # 显示 NTP 服务器配置
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        local ntp_conf="/etc/systemd/timesyncd.conf"
        local ntp_servers="(系统默认)"
        if [[ -f "$ntp_conf" ]] && grep -q '^NTP=' "$ntp_conf" 2>/dev/null; then
            ntp_servers=$(grep '^NTP=' "$ntp_conf" | sed 's/^NTP=//')
        fi
        echo "NTP 服务器: $ntp_servers (timesyncd)"
    elif command_exists chronyc 2>/dev/null; then
        echo "NTP 服务器: (chrony，用 chronyc sources 查看)"
    elif command_exists ntpq 2>/dev/null; then
        echo "NTP 服务器: (ntpd，用 ntpq -p 查看)"
    fi
    local fd_state ssh_state
    if [[ -f /etc/security/limits.d/99-unix-script.conf ]]; then fd_state="✅ 已优化"; else fd_state="默认"; fi
    if [[ -f /etc/ssh/sshd_config.d/99-unix-script.conf ]]; then ssh_state="✅ 已加固"; else ssh_state="默认"; fi
    echo "文件描述符上限: $fd_state"
    echo "SSH 加固: $ssh_state"
}

usage() {
    cat <<EOF
用法: $0 {mirror|timezone|ntp|optimize|ssh|autoupdate|all|status|help}  (仅 Linux)

  mirror      更换软件源为国内镜像（Debian/Ubuntu/CentOS）
  timezone    设置时区并启用 NTP 时间同步（默认 Asia/Shanghai）
  ntp         配置自定义 NTP 服务器（阿里云/清华/华为/Google/自定义）
  optimize    优化系统参数（文件描述符、TCP、内核）
  ssh         SSH 加固（禁用密码登录、禁用 root 直登，需先配好密钥）
  autoupdate  启用自动安全更新
  all         依次执行以上全部
  status      查看各项配置状态
EOF
}

main() {
    local action="${1:-help}"
    detect_os
    case "$action" in
        mirror)     do_mirror ;;
        timezone)   do_timezone ;;
        ntp)        do_ntp ;;
        optimize)   do_optimize ;;
        ssh)        do_ssh ;;
        autoupdate) do_autoupdate ;;
        all)        do_all ;;
        status)     status_sys_setup ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
