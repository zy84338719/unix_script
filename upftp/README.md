# upftp（轻量级 FTP 文件分享工具）

安装 [upftp](https://github.com/zy84338719/upftp) —— Go 编写的即开即用 FTP 文件分享工具。一条命令把本地目录变成可下载的 FTP + HTTP 文件服务。Linux + macOS。

## 特性
- **即开即用**：零配置，启动即匿名访问，自动打印地址
- **多形态访问**：FTP 客户端 + Web 界面（拖拽上传/一键下载）+ TUI 终端界面
- **扫码下载**：TUI 中选文件生成二维码，手机扫码即下
- **沙箱安全**：所有路径限制在共享根目录内
- **轻量无依赖**：单一二进制（~11MB），无需运行时环境

## 安装

```bash
chmod +x upftp/install.sh
./upftp/install.sh            # 安装（默认动作）
```

macOS 优先 `brew install upftp`，否则从 GitHub Releases 下载二进制。

## 使用

```bash
upftp                          # 分享当前目录（FTP 2121 / HTTP 8080）
upftp -d /shared -p 3000       # 指定目录和端口
upftp -user admin -pass 123    # 带认证
upftp --read-only              # 只读模式
upftp --tui=false              # 后台服务模式
```

浏览器打开 `http://<你的IP>:8080` 访问 Web 界面。

## 状态与卸载

```bash
./upftp/install.sh status
./upftp/install.sh uninstall
```

## 说明
- 版本通过 GitHub API 获取，CI 中带 GH_TOKEN 认证。
- 支持 x86_64 / ARM64，Linux + macOS。
- 文档：https://github.com/zy84338719/upftp
