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
