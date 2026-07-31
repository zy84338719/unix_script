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
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

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

    local distro=""
    if [[ -f /etc/debian_version ]]; then
        distro="debian"
        # 区分 Debian / Ubuntu（看是否有 /etc/lsb-release 且 ID=ubuntu）
        if [[ -f /etc/os-release ]] && grep -q '^ID=ubuntu' /etc/os-release 2>/dev/null; then
            distro="ubuntu"
        fi
    elif [[ -f /etc/centos-release ]] || [[ -f /etc/redhat-release ]]; then
        distro="centos"
    fi

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
        centos)
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
        *)
            warn "无法识别发行版，跳过换源。当前支持 Debian/Ubuntu/CentOS。"
            ;;
    esac
}

# -------- 2. 时区 + 时间同步 --------
do_timezone() {
    preflight
    info "🕐 设置时区为 Asia/Shanghai 并启用时间同步"

    if command_exists timedatectl; then
        sudo timedatectl set-timezone Asia/Shanghai
        success "时区已设置为 Asia/Shanghai"
        # 优先启用 systemd-timesyncd
        if systemctl list-unit-files 2>/dev/null | grep -q systemd-timesyncd; then
            sudo systemctl enable --now systemd-timesyncd 2>/dev/null || true
            sudo timedatectl set-ntp true 2>/dev/null || true
            success "已启用 systemd-timesyncd (NTP)"
        fi
    else
        sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        success "时区已设置为 Asia/Shanghai（符号链接）"
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
            sudo apt-get install -y unattended-upgrades apt-listchanges
            sudo dpkg-reconfigure -fnoninteractive -plow unattended-upgrades 2>/dev/null || true
            success "已启用 Debian/Ubuntu 自动安全更新（unattended-upgrades）"
            ;;
        dnf|yum)
            # dnf-automatic / yum-cron
            if command_exists dnf; then
                sudo dnf install -y dnf-automatic
                sudo sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null || true
                sudo systemctl enable --now dnf-automatic.timer 2>/dev/null || true
                success "已启用 dnf-automatic"
            else
                sudo yum install -y yum-cron
                sudo systemctl enable --now yum-cron 2>/dev/null || true
                success "已启用 yum-cron"
            fi
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
    local fd_state ssh_state
    if [[ -f /etc/security/limits.d/99-unix-script.conf ]]; then fd_state="✅ 已优化"; else fd_state="默认"; fi
    if [[ -f /etc/ssh/sshd_config.d/99-unix-script.conf ]]; then ssh_state="✅ 已加固"; else ssh_state="默认"; fi
    echo "文件描述符上限: $fd_state"
    echo "SSH 加固: $ssh_state"
}

usage() {
    cat <<EOF
用法: $0 {mirror|timezone|optimize|ssh|autoupdate|all|status|help}  (仅 Linux)

  mirror      更换软件源为国内镜像（Debian/Ubuntu/CentOS）
  timezone    设置时区 Asia/Shanghai 并启用 NTP 时间同步
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
