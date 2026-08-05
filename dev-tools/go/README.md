# Go（Golang）

安装 [Go](https://go.dev/) —— 官方二进制 tarball 方式，装到 `/usr/local/go`，自动配置 PATH。Linux + macOS。

## 安装
```bash
chmod +x go/install.sh
./go/install.sh            # 安装（默认动作，需 sudo）
```
下载官方 tarball 解压到 `/usr/local/go`，并自动为 bash/zsh/profile 添加 PATH。

## 使用
```bash
go version          # 查看版本
go env GOPATH       # 查看 GOPATH
go run main.go      # 运行
go build            # 编译
```

## 状态与卸载
```bash
./go/install.sh status
./go/install.sh uninstall   # 删除 /usr/local/go，保留 ~/go 数据
```

## 说明
- 版本通过 GitHub API（golang/go releases）获取，CI 中带 GH_TOKEN 认证。
- 卸载保留 GOPATH（~/go）数据，可手动删除。
