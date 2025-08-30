# 🚀 SSR-Plus 一键管理脚本

基于 **Docker** 的 ShadowsocksR 管理脚本，支持一键安装、修改配置、启动/停止服务、启用 BBR 加速等操作。  
适合需要快速部署、管理 SSR 服务的用户。

---

## ✅ 支持系统

**Debian 系列**
- Debian 9 (stretch)  
- Debian 10 (buster)  
- Debian 11 (bullseye)  
- Debian 12 (bookworm)  
- Debian 13 (trixie)  

**Ubuntu 系列**
- Ubuntu 18.04 LTS (bionic)  
- Ubuntu 20.04 LTS (focal)  
- Ubuntu 22.04 LTS (jammy)  
- Ubuntu 24.04 LTS (noble)  
- Ubuntu 25.04 (plucky)  

⚠️ 其他系统（CentOS / Rocky / Fedora / openSUSE 等）理论上也可用，  
但可能因软件源或依赖问题需要手动调整，请谨慎使用。

---

## 📥 安装/更新脚本

```bash
wget -O ssr-plus.sh https://raw.githubusercontent.com/Alvin9999/SSR-Plus/main/ssr-plus.sh
chmod +x ssr-plus.sh
bash ssr-plus.sh
```

## 📖 功能菜单

==============================
🚀 SSR-Plus 管理脚本 v1.1.2 🚀
==============================

1) 安装 SSR
2) 修改配置
3) 查看配置
4) 启动 SSR
5) 停止 SSR
6) 重启 SSR
7) 卸载 SSR
8) 启用系统加速 (BBR + TFO)
9) 退出

==============================
系统加速状态: 已启用 / 未启用
SSR 当前状态: 已启动 / 已停止 / 未安装
==============================

## 🔑 示例配置展示

### 当前 SSR 配置
| 参数       | 值                |
|------------|-------------------|
| 🌐 服务器   | 1.1.1.1           |
| 🔌 端口     | 20000             |
| 🔑 密码     | dongtaiwang.com   |
| 🔒 加密方式 | chacha20-ietf     |
| 📜 协议     | auth_chain_a      |
| 🎭 混淆     | tls1.2_ticket_auth |


SSR 链接:
ssr://MjAzLjAmF1dGhfY2hhaW5fYTpj...（示例）


## ⚡ 系统加速（BBR + TCP Fast Open）

### 功能说明
- 🚀 一键启用 TCP Fast Open  
- 🚀 一键启用 Google BBR 拥塞控制  

### 当前状态
| 功能项        | 状态                  |
|---------------|-----------------------|
| ⚡ 系统加速    | 已启用 / 未启用       |
| 🔧 内核版本检查 | < 4.9 可能无法启用 BBR |

### 验证方法
启用后可通过以下命令验证是否生效： 

```bash
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
```

## 🧭 使用说明

### 基础操作流程
1. **首次运行** → 选择 `1) 安装 SSR`，按提示填写端口、密码、加密方式、协议、混淆。  
2. **修改配置** → 选择 `2) 修改配置`（修改端口会自动重建容器并重新映射端口）。  
3. **查看参数** → 选择 `3) 查看配置`，可获取当前参数与导入链接。  

---

### 服务控制
| 功能项 | 操作说明 |
|--------|----------|
| ▶️ 启动服务 | `4) 启动 SSR` |
| ⏹ 停止服务 | `5) 停止 SSR` |
| 🔄 重启服务 | `6) 重启 SSR` |

---

### 清理卸载
| 功能项 | 操作说明 |
|--------|----------|
| 🗑 卸载服务 | `7) 卸载 SSR`（会停止并移除容器与镜像，删除配置文件） |

---

### 网络加速
| 功能项 | 操作说明 |
|--------|----------|
| ⚡ 启用加速 | `8) 启用系统加速 (BBR + TFO)` |

---

### 说明
- 📦 脚本默认在 **Docker 容器** 中运行 SSR  
- ⚙️ 配置文件路径： /etc/shadowsocks-r/config.json
 
## 🛠 常见问题（FAQ）

| ❓ 问题 | 💡 解决方法 |
|---------|-------------|
| **安装 Docker 失败？** | 1. 确认系统软件源可访问，系统时间已同步。<br>2. 在 Debian/Ubuntu 上执行：`apt-get update` 后再运行脚本。<br>3. 国内网络环境请配置代理或更换可访问的软件源。 |
| **CentOS 安装报错？** | 1. CentOS 7/8 默认源可能缺少 `docker-ce`。<br>2. 建议先**手动安装 Docker**，再运行脚本。 |
| **SSR 无法启动？** | 1. 检查配置文件 `/etc/shadowsocks-r/config.json` 是否正确。<br>2. 确认端口未被占用，可用 `netstat -tunlp | grep 端口号` 检查。 |
| **系统加速未生效？** | 1. 确认内核版本 ≥ 4.9。<br>2. 执行：`sysctl net.ipv4.tcp_congestion_control` 应输出 `bbr`。<br>3. 执行：`sysctl net.core.default_qdisc` 应输出 `fq`。 |

---

📌 **小贴士**  
- 修改配置后记得 **重启 SSR 服务** (`6) 重启 SSR`)。  
- 如果依赖缺失或脚本报错，可尝试 **手动安装缺少的软件包** 再重新运行脚本。  



## 📌 版本更新日志

| 版本号 | 日期      | 更新内容 |
|--------|-----------|----------|
| v1.1.2 | 2025-08   | - 优化菜单显示，增加状态检测（已安装 / 已启动 / 已停止）<br>- 增加 BBR 检测与启用功能<br>- 修复部分系统下 Docker 安装失败的问题 |
| v1.1.1 | 2025-08   | - 修复部分系统下 SSR 启动失败的问题<br>- 增强 Docker 安装脚本兼容性 |
| v1.1.0 | 2025-08   | - 支持 Debian 12、Ubuntu 24.04<br>- 增加配置导出功能 |
| v1.0.0 | 2025-08   | - 初始版本，支持一键安装/管理 SSR<br>- 提供 Docker 化部署方案 |
