#!/usr/bin/env bash
#
# essentials/sys-setup/platform/rhel.sh
#
# RHEL 族（DISTRO_FAMILY=rhel）平台实现。
# 覆盖 DISTRO_ID：centos / almalinux / rocky / fedora / openeuler / anolis；
# rhel / kylin(服务器) 无公开镜像，降级指引。
# 镜像站按发行版固定（2026-08-28 逐站实测）：
#   almalinux→阿里云   rocky→USTC(主版本目录)   fedora/openeuler→TUNA
#   anolis→阿里云(sed)   centos stream→TUNA(现状)

_rhel_backup_repos() {
    local ts="$1"
    sudo cp -a /etc/yum.repos.d "/etc/yum.repos.d.bak.$ts" 2>/dev/null || true
}

# Rocky 的 $releasever 展开为 9.6 这类小版本，而 USTC 目录按主版本组织
# （/rocky/9/ ✅、/rocky/9.6/ ❌，2026-08-28 实测），URL 与 gpgkey 均用主版本。
_rhel_major() {
    local m vid
    m=$(rpm -E '%{rhel}' 2>/dev/null || true)
    if [[ "$m" =~ ^[0-9]+$ ]]; then echo "$m"; return; fi
    vid=$(uxs_os_release VERSION_ID)
    echo "${vid%%.*}"
}

plat_mirror_preview() {
    case "$DISTRO_ID" in
        centos)
            echo "  1. $(_t 'Back up /etc/yum.repos.d')"
            echo "  2. $(_t 'Rewrite centos.repo to Tsinghua TUNA (CentOS Stream)')"
            echo "  3. dnf/yum clean all + makecache" ;;
        almalinux)
            echo "  1. $(_t 'Back up /etc/yum.repos.d')"
            echo "  2. $(_t 'Rewrite almalinux.repo to point to the Aliyun mirror')"
            echo "  3. dnf/yum clean all + makecache" ;;
        rocky)
            echo "  1. $(_t 'Back up /etc/yum.repos.d')"
            echo "  2. $(_t 'Rewrite rocky.repo to point to the USTC mirror (major version path)')"
            echo "  3. dnf/yum clean all + makecache" ;;
        fedora)
            echo "  1. $(_t 'Back up /etc/yum.repos.d')"
            echo "  2. $(_t 'Rewrite fedora.repo and fedora-updates.repo to point to Tsinghua TUNA')"
            echo "  3. dnf/yum clean all + makecache" ;;
        openeuler)
            echo "  1. $(_t 'Back up /etc/yum.repos.d')"
            echo "  2. $(_t 'sed: replace the openEuler sources with Tsinghua TUNA')"
            echo "  3. dnf/yum clean all + makecache" ;;
        anolis)
            echo "  1. $(_t 'Back up /etc/yum.repos.d')"
            echo "  2. $(_t 'sed: replace the openAnolis sources with the Aliyun mirror')"
            echo "  3. dnf/yum clean all + makecache" ;;
        *)
            echo "  1. $(_tf '%s: no public mirror, guidance only (no system change)' "${DISTRO_ID}")" ;;
    esac
}

plat_mirror_apply() {
    local ts
    ts=$(date +%s)
    case "$DISTRO_ID" in
        centos)
            # 通过 os-release 的 NAME 区分 CentOS Stream 与 EOL 老版
            local is_stream
            is_stream=$(uxs_os_release NAME | grep -qi stream && echo yes || echo no)
            _rhel_backup_repos "$ts"
            if [[ "$is_stream" == "yes" ]]; then
                sudo tee /etc/yum.repos.d/centos.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— CentOS Stream 清华 TUNA 镜像
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
                success "$(_t 'CentOS Stream source switched to the Tsinghua mirror (repos backed up)')"
            else
                warn "$(_tf 'CentOS 7/8 (EOL) refer to the vault: %s' "https://mirrors.tuna.tsinghua.edu.cn/help/centos-vault/")"
                warn "$(_tf 'Original /etc/yum.repos.d backed up to .bak.%s, replace baseurl' "${ts}")"
            fi
            ;;
        almalinux)
            # Alma 的 $releasever 无小版本（=9），可原生交给 dnf 展开
            _rhel_backup_repos "$ts"
            sudo tee /etc/yum.repos.d/almalinux.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— AlmaLinux 阿里云镜像
[BaseOS]
name=AlmaLinux $releasever - BaseOS
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/BaseOS/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever

[AppStream]
name=AlmaLinux $releasever - AppStream
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/AppStream/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever

[CRB]
name=AlmaLinux $releasever - CRB
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/CRB/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever

[extras]
name=AlmaLinux $releasever - Extras
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/extras/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever
EOF
            success "$(_t 'AlmaLinux source switched to the Aliyun mirror (repos.d backed up)')"
            ;;
        rocky)
            local major
            major=$(_rhel_major)
            _rhel_backup_repos "$ts"
            # 此 heredoc 有意不带引号：${major} 需展开；$basearch 转义保留给 dnf
            sudo tee /etc/yum.repos.d/rocky.repo >/dev/null <<EOF
# 由 unix_script sys-setup 生成 —— Rocky Linux 中科大 USTC 镜像（主版本 ${major}）
[BaseOS]
name=Rocky Linux ${major} - BaseOS
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/BaseOS/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}

[AppStream]
name=Rocky Linux ${major} - AppStream
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/AppStream/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}

[CRB]
name=Rocky Linux ${major} - CRB
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/CRB/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}

[Extras]
name=Rocky Linux ${major} - Extras
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/Extras/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}
EOF
            success "$(_t 'Rocky Linux source switched to the USTC mirror (repos.d backed up)')"
            ;;
        fedora)
            # TUNA 帮助页核对：updates 路径无 /os 后缀；老版本已移 archive 保持默认
            _rhel_backup_repos "$ts"
            sudo tee /etc/yum.repos.d/fedora.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— Fedora 清华 TUNA 镜像
[fedora]
name=Fedora $releasever - $basearch
baseurl=https://mirrors.tuna.tsinghua.edu.cn/fedora/releases/$releasever/Everything/$basearch/os/
#metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch
EOF
            sudo tee /etc/yum.repos.d/fedora-updates.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— Fedora updates 清华 TUNA 镜像
[updates]
name=Fedora $releasever - $basearch - Updates
baseurl=https://mirrors.tuna.tsinghua.edu.cn/fedora/updates/$releasever/Everything/$basearch/
#metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch
EOF
            success "$(_t 'Fedora source switched to the Tsinghua mirror (repos.d backed up)')"
            ;;
        openeuler)
            _rhel_backup_repos "$ts"
            sudo sed -i.bak \
                -e 's|mirror.openeuler.org|mirrors.tuna.tsinghua.edu.cn/openeuler|g' \
                -e 's|repo.openeuler.org|mirrors.tuna.tsinghua.edu.cn/openeuler|g' \
                /etc/yum.repos.d/*.repo 2>/dev/null || true
            success "$(_t 'openEuler source replaced by the Tsinghua mirror (repos backed *.bak)')"
            ;;
        anolis)
            _rhel_backup_repos "$ts"
            sudo sed -i.bak \
                -e 's|mirrors.openanolis.cn|mirrors.aliyun.com/anolis|g' \
                -e 's|mirrors.anolis.org|mirrors.aliyun.com/anolis|g' \
                /etc/yum.repos.d/*.repo 2>/dev/null || true
            success "$(_t 'Anolis OS source replaced by the Aliyun mirror (repos backed up *.bak)')"
            ;;
        *)
            warn "$(_t 'RHEL/Kylin (server) has no public mirror, the system sources are kept')"
            warn "$(_t 'RHEL: use subscription-manager; Kylin: use the built-in update source')"
            ;;
    esac
    sudo dnf clean all 2>/dev/null || sudo yum clean all 2>/dev/null || true
    sudo dnf makecache 2>/dev/null || sudo yum makecache 2>/dev/null || true
}

plat_autoupdate() {
    if command -v dnf >/dev/null 2>&1; then
        pkg_install dnf-automatic
        sudo sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null || true
        uxs_svc enable-now dnf-automatic.timer
        success "$(_t 'dnf-automatic has been enabled')"
    else
        pkg_install yum-cron
        uxs_svc enable-now yum-cron
        success "$(_t 'yum-cron has been enabled')"
    fi
}
