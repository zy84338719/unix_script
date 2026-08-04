#compdef uxs

# unix_script / uxs Zsh 自动补全
# 用法：source completions/uxs.zsh
# 或复制到 $fpath 并 compinit

_uxs() {
    local -a modules globals subcmds

    modules=(
        'bbr:BBR 网络加速'
        'bun:Bun 运行时'
        'clash:Clash (mihomo) 代理'
        'cockpit:Cockpit 管理面板'
        'ddns-go:动态域名解析'
        'deno:Deno 运行时'
        'deskflow:键鼠共享'
        'dev-enhance:开发工具增强'
        'dev-mirror:开发换源加速'
        'dev-tui:终端 TUI 工具'
        'docker:Docker 容器引擎'
        'docker-image:Docker 镜像导出'
        'essential-pkgs:装机必备工具包'
        'fail2ban:SSH 暴力破解防护'
        'go:Go 语言环境'
        'grafana:Grafana 监控面板'
        'gitea:Gitea 自托管 Git'
        'k7s:Kubernetes 桌面监控'
        'minikube:本地 Kubernetes'
        'modern-cli:现代 CLI 工具'
        'multi-net:多网卡策略路由'
        'nginx:Nginx Web 服务器'
        'node_exporter:Prometheus 节点导出器'
        'nvm:Node.js 版本管理'
        'ollama:本地大模型运行时'
        'opencode:终端 AI 编程助手'
        'openlist:文件列表/网盘聚合'
        'pi:Pi AI 编程代理'
        'pnpm:Node.js 包管理器'
        'postgres:PostgreSQL 数据库'
        'prometheus:Prometheus 监控系统'
        'process_manager_tool:进程管理工具'
        'redis:Redis 内存数据库'
        'restic:Restic 备份工具'
        'caddy:Caddy Web 服务器'
        'rust:Rust 语言环境'
        'safe-rm:安全删除'
        'shutdown_timer:定时关机'
        'swap:Swap 虚拟内存'
        'sys-cmd:系统诊断命令'
        'sys-setup:系统初始化配置'
        'tailscale:Tailscale VPN'
        'ufw:UFW 防火墙'
        'upftp:FTP 文件分享'
        'uptime-kuma:服务可用性监控'
        'wireguard:WireGuard VPN'
        'zsh_setup:Zsh & Oh My Zsh'
    )

    globals=(
        '--status:查看所有模块状态'
        '--status-json:JSON 格式状态'
        '--list:列出模块名'
        '--list-modules:列出模块及子命令'
        '--list-categories:列出模块分类'
        '--version:查看版本'
        '--help:帮助信息'
        'update:更新到最新版'
        'cli:安装全局命令 uxs'
        'doctor:环境诊断'
        'scaffold:创建新模块模板'
    )

    _arguments -C \
        '1: :->first_arg' \
        '2: :->second_arg' \
        '*:: :->rest'

    case $state in
        first_arg)
            _describe -t modules '模块' modules
            _describe -t globals '全局选项' globals
            ;;
        second_arg)
            case $words[2] in
                bbr)              subcmds=('enable' 'disable' 'status' 'help') ;;
                bun)              subcmds=('install' 'mirror' 'unmirror' 'uninstall' 'status' 'help') ;;
                clash)            subcmds=('config' 'example' 'install' 'restart' 'start' 'status' 'stop' 'tun-off' 'tun-on' 'uninstall') ;;
                docker)           subcmds=('install' 'mirror' 'registry' 'uninstall' 'status' 'help') ;;
                docker-image)     subcmds=('save' 'status' 'help') ;;
                multi-net)        subcmds=('clear' 'list' 'route-port' 'route-user' 'setup' 'status') ;;
                ollama)           subcmds=('install' 'pull' 'status' 'uninstall' 'help') ;;
                safe-rm)          subcmds=('install' 'on' 'off' 'status' 'uninstall' 'help') ;;
                sys-cmd)          subcmds=('all' 'status') ;;
                sys-setup)        subcmds=('mirror' 'timezone' 'ntp' 'optimize' 'ssh' 'autoupdate' 'all' 'status' 'help') ;;
                tailscale)        subcmds=('install' 'uninstall' 'status') ;;
                shutdown_timer)   subcmds=('status') ;;
                *)                subcmds=('install' 'uninstall' 'status' 'help') ;;
            esac
            _describe -t subcmds '子命令' subcmds
            ;;
    esac
}

_uxs "$@"
