# kind

用 Docker 容器当节点起本地 Kubernetes 集群——CI/多集群测试常用，minikube 的轻量替代。
运行依赖 docker（框架自动先装）。

```bash
./install.sh kind                      # 安装
kind create cluster --name demo        # 起集群
kind delete clusters --all             # 清理
```
