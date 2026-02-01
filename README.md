# K3s Installer (OpenClaw Edition)

这是一个针对国内环境优化的 K3s 自动安装脚本。集成自动测速与自愈机制，确保在复杂网络环境下依然拥有极高的安装成功率。

---

## 核心特性

- **国内优选**：并行测试所有镜像源 TTFB (Time to First Byte) 耗时，动态生成最优 `registries.yaml`。
- **远程同步**：自动从本仓库拉取最新的分类镜像列表（Docker/GCR/Quay/GHCR/K8s 等）。
- **三级自愈 (Triple-Jump)**：`远程主列表` → `7日定期备份 (.bak)` → `脚本内置硬编码源`，实现多重逻辑兜底。
- **Geo自适应**：自动检测出口 IP。国内环境全自动启用 GitHub 加速代理（支持 gh-proxy.org、ghfast.top 等池化选择）。
- **生产预设**：针对 8C16G 节点优化资源预留（Kube-Reserved/System-Reserved），提升系统在高负载下的稳定性。
- **全系统兼容**：原生支持 **Systemd** (Ubuntu/Debian/Fedora/CentOS) 与 **OpenRC** (Alpine Linux)。

---

## 仓库结构

- **`*.txt`**: 各类镜像源列表（每行一个域名），包括 `docker.txt`, `gcr.txt`, `ghcr.txt`, `k8s.txt`, `quay.txt` 等。
- **`*.txt.bak`**: 由 GitHub Actions 自动生成的备份文件，保留上一周期的有效源数据。
- **`.github/workflows/`**: 包含每周自动巡检、存活剔除及备份更新的流水线配置文件。

---

## 快速开始

一键install脚本：

```bash
curl -sfL [https://gh-proxy.org/https://raw.githubusercontent.com/weix2025/k3s-installer/main/install.sh](https://gh-proxy.org/https://raw.githubusercontent.com/weix2025/k3s-installer/main/install.sh) | bash
