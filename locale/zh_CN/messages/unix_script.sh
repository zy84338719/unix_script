# 本文件由 po/messages.sh 生成，请勿手改。
# 纯 bash 兜底查表：没有 gettext 时 _t 用它出译文。
# 域：unix_script
_sk_msg_lookup_unix_script() {
  case "$1" in
    '1Panel is Linux-only. Current: ') printf '%s' '1Panel 仅支持 Linux。当前：' ;;
    'systemctl (systemd) is required.') printf '%s' '需要 systemctl（systemd）。' ;;
    'Either curl or wget is required, please install one first.') printf '%s' '需要 curl 或 wget 之一，请先安装。' ;;
    'Detected 1Panel installed (') printf '%s' '检测到 1Panel 已安装（' ;;
    'Unknown version') printf '%s' '未知版本' ;;
    ')') printf '%s' '）' ;;
    'Continue and reinstall/update'\?) printf '%s' '是否继续并重装/更新？' ;;
    'Cancelled') printf '%s' '已取消' ;;
    'Downloading official installer (') printf '%s' '下载官方安装脚本（' ;;
    ')...') printf '%s' '）...' ;;
    'Running official installer (non-interactive if PANEL_'\*' env vars are set)...') printf '%s' '执行官方安装脚本（如已设置 PANEL_* 环境变量则按其非交互安装）...' ;;
    'Party popper 1Panel installation complete!') printf '%s' '🎉 1Panel 安装完成！' ;;
    'View panel address/security entry/account: sudo 1pctl user-info') printf '%s' '查看面板地址/安全入口/账号：sudo 1pctl user-info' ;;
    'Common commands: 1pctl status | 1pctl restart | 1pctl update') printf '%s' '常用命令：1pctl status | 1pctl restart | 1pctl update' ;;
    'Installer ran but 1pctl was not detected — check the output above to confirm the result.') printf '%s' '安装脚本已执行，但未检测到 1pctl——请检查上方输出确认安装结果。' ;;
    '1Panel is not installed.') printf '%s' '1Panel 未安装。' ;;
    '1Panel is not installed, nothing to uninstall.') printf '%s' '1Panel 未安装，无需卸载。' ;;
    'Confirm uninstall of 1Panel'\?) printf '%s' '确认卸载 1Panel？' ;;
    '1Panel uninstalled.') printf '%s' '1Panel 已卸载。' ;;
    'Not installed') printf '%s' '未安装' ;;
    'Installed and running') printf '%s' '已安装并运行' ;;
    'Upgrade 1Panel (1pctl update)') printf '%s' '升级 1Panel（1pctl update）' ;;
    'Uninstall 1Panel (keep data directory)') printf '%s' '卸载 1Panel（保留数据目录）' ;;
    'Unknown action: ') printf '%s' '未知操作: ' ;;
    'Detected installed Docker') printf '%s' '检测到已安装 Docker' ;;
    'Continue and try to update'\?) printf '%s' '是否继续并尝试更新？' ;;
    'Installing Docker via domestic mirror script (linuxmirrors.cn)...') printf '%s' '使用国内镜像源一键脚本（linuxmirrors.cn）安装/换源 Docker...' ;;
    'Domestic mirror script failed, try the official installer instead') printf '%s' '国内镜像源安装脚本执行失败，可改用官方源重试' ;;
    'Installing Docker via pacman...') printf '%s' '通过 pacman 安装 Docker...' ;;
    'Install failed') printf '%s' '安装失败' ;;
    'Installing Docker via apk...') printf '%s' '通过 apk 安装 Docker...' ;;
    'Installing Docker via zypper...') printf '%s' '通过 zypper 安装 Docker...' ;;
    'Installing Docker Engine via official script (get.docker.com)...') printf '%s' '使用官方一键脚本安装 Docker Engine（get.docker.com）...' ;;
    'Official installer failed, check the network or install manually:') printf '%s' '官方安装脚本执行失败，请检查网络或参考以下链接手动安装:' ;;
    'Enabling and starting docker service...') printf '%s' '启用并启动 docker 服务...' ;;
    'Current user is already in the docker group') printf '%s' '当前用户已在 docker 组中' ;;
    'Add user') printf '%s' '是否将用户' ;;
    'to the docker group (passwordless docker, requires re-login)'\?) printf '%s' '加入 docker 组（免 sudo 使用 docker，需重新登录生效）？' ;;
    'For standalone docker-compose, see:') printf '%s' '如需独立 docker-compose，请参考:' ;;
    'Docker installed: ') printf '%s' 'Docker 已安装：' ;;
    'Docker Desktop is recommended on macOS.') printf '%s' 'macOS 上推荐使用 Docker Desktop。' ;;
    'Install Docker Desktop via Homebrew (--cask)'\?) printf '%s' '是否通过 Homebrew 安装 Docker Desktop（--cask）？' ;;
    'Installation complete. Please launch Docker Desktop to finish setup.') printf '%s' '安装完成，请启动 Docker Desktop 应用以完成初始化。' ;;
    'Please download and install manually:') printf '%s' '请手动下载安装:' ;;
    'Rocket Starting Docker installation') printf '%s' '🚀 开始安装 Docker' ;;
    'Party popper Docker installation flow complete') printf '%s' '🎉 Docker 安装流程结束' ;;
    'Verify:') printf '%s' '验证：' ;;
    'Test run (first pull is slow)') printf '%s' '测试运行（首次拉取镜像较慢）' ;;
    'Please uninstall Docker Desktop manually.') printf '%s' '请手动卸载 Docker Desktop。' ;;
    'Uninstalling will stop the docker service and remove the package.') printf '%s' '卸载将停止 docker 服务并移除软件包。' ;;
    'Confirm uninstall of Docker Engine'\?) printf '%s' '确认卸载 Docker Engine？' ;;
    'Data directory deleted.') printf '%s' '数据目录已删除。' ;;
    'Docker uninstalled.') printf '%s' 'Docker 已卸载。' ;;
    'Installed but service not running') printf '%s' '已安装但服务未运行' ;;
    'Registry mirror configuration (linuxmirrors) is Linux-only. Current: ') printf '%s' '镜像加速器换源（linuxmirrors）仅支持 Linux。当前：' ;;
    'Still continue'\?) printf '%s' '仍然继续？' ;;
    'Registry mirror configuration complete.') printf '%s' '镜像加速器换源完成。' ;;
    'If Docker is already running, restart it to apply:') printf '%s' '如已运行 Docker，可重启使配置生效:' ;;
    'Domestic mirror installation (linuxmirrors) is Linux-only. Current: ') printf '%s' '国内镜像源安装（linuxmirrors）仅支持 Linux。当前：' ;;
    'Domestic mirror script failed, check the network') printf '%s' '国内镜像源安装脚本执行失败，请检查网络' ;;
    'Docker mirror installation/replacement complete.') printf '%s' 'Docker 镜像源安装/换源完成。' ;;
    'Common commands:') printf '%s' '常用命令:' ;;
    'View registry mirror') printf '%s' '查看镜像加速器' ;;
    'Install or update Docker (optional domestic mirror)') printf '%s' '安装或更新 Docker（可选国内镜像源）' ;;
    'Configure registry mirror only (no reinstall, Linux only)') printf '%s' '仅更换 Docker 镜像加速器（不重装 Docker，仅 Linux）' ;;
    'Uninstall Docker') printf '%s' '卸载 Docker' ;;
    'View installation and running status') printf '%s' '查看安装与运行状态' ;;
    *) return 1 ;;
  esac
}
