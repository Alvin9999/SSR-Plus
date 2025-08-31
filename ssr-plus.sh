#!/bin/bash
# 🚀 SSR-Plus Docker 管理脚本
# 支持 Debian/Ubuntu/CentOS/RHEL/Rocky/AlmaLinux/Fedora/openSUSE
# 版本号: v1.1.3

stty erase ^H   # 让退格键在终端里正常工作

DOCKER_IMAGE="yinqishuo/ssr:0.01"
CONTAINER_NAME="ssr"
CONFIG_PATH="/etc/shadowsocks-r/config.json"

# ========== 样式 ==========
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
NC='\e[0m' # No Color

INDENT=" "   # 缩进 1 格
VERSION="v1.1.3"

# ========== 系统检测 ==========
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  else
    OS=$(uname -s)
  fi
}

# ========== Docker 安装 ==========
install_docker() {
  detect_os
  echo -e "${BLUE}${INDENT}[1/4] 安装 Docker... 系统: $OS${NC}"

  case "$OS" in
    ubuntu|debian)
      apt-get update -y
      apt-get install -y ca-certificates curl gnupg lsb-release
      mkdir -p /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      apt-get update -y
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    centos|rhel)
      yum install -y yum-utils device-mapper-persistent-data lvm2 || {
        echo -e "${RED}${INDENT}❌ yum-utils 安装失败，请先清理缓存后再运行:${NC}"
        echo -e "${YELLOW}${INDENT}执行: yum clean all && rm -rf /var/cache/yum${NC}"
        exit 1
      }
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      yum install -y docker-ce docker-ce-cli containerd.io || {
        echo -e "${RED}${INDENT}❌ Docker 安装失败，请检查网络或清理 yum 缓存后重试${NC}"
        exit 1
      }
      ;;
    rocky|almalinux)
      dnf install -y dnf-plugins-core
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    fedora)
      dnf install -y dnf-plugins-core
      dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    opensuse*|sles)
      zypper install -y docker docker-runc
      ;;
    *)
      echo -e "${RED}${INDENT}⚠️ 未知系统，请手动安装 Docker${NC}"
      exit 1
      ;;
  esac

  # 验证 Docker 是否安装成功
  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}${INDENT}❌ Docker 未安装成功，请手动检查系统环境${NC}"
    exit 1
  fi

  systemctl enable docker
  systemctl start docker
}

# ========== SSR 状态检测 ==========
check_ssr_status() {
  if ! command -v docker >/dev/null 2>&1; then
    SSR_STATUS="${RED}未安装 (Docker 未安装)${NC}"
    return
  fi

  if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    SSR_STATUS="${RED}未安装${NC}"
    return
  fi

  # 容器存在
  if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" != "true" ]; then
    SSR_STATUS="${YELLOW}容器已停止${NC}"
    return
  fi

  # 容器运行中，检查 SSR 进程
  if docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1; then
    SSR_STATUS="${GREEN}已启动${NC}"
  else
    SSR_STATUS="${YELLOW}容器运行中 (SSR 进程未运行)${NC}"
  fi
}

# ========== BBR 检测 ==========
check_bbr() {
  local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

  if [[ "$cc" == "bbr" && "$qdisc" == "fq" ]]; then
    BBR_STATUS="${GREEN}已启用 BBR${NC}"
  else
    BBR_STATUS="${RED}未启用 BBR${NC}"
  fi
}

# ========== 菜单选择 ==========
choose_method() {
  echo -e "\n${CYAN}${INDENT}请选择加密方式:${NC}"
  echo "${INDENT}1) none"
  echo "${INDENT}2) rc4"
  echo "${INDENT}3) rc4-md5"
  echo "${INDENT}4) rc4-md5-6"
  echo "${INDENT}5) aes-128-ctr"
  echo "${INDENT}6) aes-192-ctr"
  echo "${INDENT}7) aes-256-ctr"
  echo "${INDENT}8) aes-128-cfb"
  echo "${INDENT}9) aes-192-cfb"
  echo "${INDENT}10) aes-256-cfb"
  echo "${INDENT}11) aes-128-cfb8"
  echo "${INDENT}12) aes-192-cfb8"
  echo "${INDENT}13) aes-256-cfb8"
  echo "${INDENT}14) salsa20"
  echo "${INDENT}15) chacha20"
  echo "${INDENT}16) chacha20-ietf"
  read -p "${INDENT}输入序号 [默认16]: " method
  case $method in
    1) METHOD="none" ;;
    2) METHOD="rc4" ;;
    3) METHOD="rc4-md5" ;;
    4) METHOD="rc4-md5-6" ;;
    5) METHOD="aes-128-ctr" ;;
    6) METHOD="aes-192-ctr" ;;
    7) METHOD="aes-256-ctr" ;;
    8) METHOD="aes-128-cfb" ;;
    9) METHOD="aes-192-cfb" ;;
    10) METHOD="aes-256-cfb" ;;
    11) METHOD="aes-128-cfb8" ;;
    12) METHOD="aes-192-cfb8" ;;
    13) METHOD="aes-256-cfb8" ;;
    14) METHOD="salsa20" ;;
    15) METHOD="chacha20" ;;
    16|"") METHOD="chacha20-ietf" ;;
    *) METHOD="chacha20-ietf" ;;
  esac
}

choose_protocol() {
  echo -e "\n${CYAN}${INDENT}请选择协议 (protocol):${NC}"
  echo "${INDENT}1) origin"
  echo "${INDENT}2) auth_sha1_v4"
  echo "${INDENT}3) auth_aes128_md5"
  echo "${INDENT}4) auth_aes128_sha1"
  echo "${INDENT}5) auth_chain_a"
  echo "${INDENT}6) auth_chain_b"
  read -p "${INDENT}输入序号 [默认2]: " protocol
  case $protocol in
    1) PROTOCOL="origin" ;;
    2|"") PROTOCOL="auth_sha1_v4" ;;
    3) PROTOCOL="auth_aes128_md5" ;;
    4) PROTOCOL="auth_aes128_sha1" ;;
    5) PROTOCOL="auth_chain_a" ;;
    6) PROTOCOL="auth_chain_b" ;;
    *) PROTOCOL="auth_sha1_v4" ;;
  esac
}

choose_obfs() {
  echo -e "\n${CYAN}${INDENT}请选择混淆 (obfs):${NC}"
  echo "${INDENT}1) plain"
  echo "${INDENT}2) http_simple"
  echo "${INDENT}3) http_post"
  echo "${INDENT}4) random_head"
  echo "${INDENT}5) tls1.2_ticket_auth"
  read -p "${INDENT}输入序号 [默认1]: " obfs
  case $obfs in
    1|"") OBFS="plain" ;;
    2) OBFS="http_simple" ;;
    3) OBFS="http_post" ;;
    4) OBFS="random_head" ;;
    5) OBFS="tls1.2_ticket_auth" ;;
    *) OBFS="plain" ;;
  esac
}

# ========== 配置 ==========
set_config() {
  docker exec -i $CONTAINER_NAME bash -c "mkdir -p /etc/shadowsocks-r && cat > $CONFIG_PATH" <<EOF
{
  "server":"0.0.0.0",
  "server_ipv6":"::",
  "server_port":${PORT},
  "local_address":"127.0.0.1",
  "local_port":1080,
  "password":"${PASSWORD}",
  "timeout":120,
  "method":"${METHOD}",
  "protocol":"${PROTOCOL}",
  "protocol_param":"",
  "obfs":"${OBFS}",
  "obfs_param":"",
  "redirect":"",
  "dns_ipv6":false,
  "fast_open":false,
  "workers":1
}
EOF
}

generate_ssr_link() {
  local ip=$(curl -s ifconfig.me)
  local pass_b64=$(echo -n "${PASSWORD}" | base64 -w0)
  local raw="${ip}:${PORT}:${PROTOCOL}:${METHOD}:${OBFS}:${pass_b64}/"
  local link="ssr://$(echo -n "$raw" | base64 -w0)"
  echo -e "\n${GREEN}${INDENT}SSR 链接:${NC}\n${INDENT}$link\n"
}

show_config() {
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"
    return
  fi

  if ! docker exec "$CONTAINER_NAME" test -f "$CONFIG_PATH"; then
    echo -e "${YELLOW}${INDENT}容器内未找到配置文件，请先『安装 SSR』或『修改配置』写入参数${NC}"
    return
  fi

  local cfg=$(docker exec -i $CONTAINER_NAME cat $CONFIG_PATH 2>/dev/null)
  local ip=$(curl -s ifconfig.me)

  PORT=$(echo "$cfg" | grep '"server_port"' | awk -F ':' '{print $2}' | tr -d ' ,')
  PASSWORD=$(echo "$cfg" | grep '"password"' | awk -F '"' '{print $4}')
  METHOD=$(echo "$cfg" | grep '"method"' | awk -F '"' '{print $4}')
  PROTOCOL=$(echo "$cfg" | grep '"protocol"' | awk -F '"' '{print $4}')
  OBFS=$(echo "$cfg" | grep '"obfs"' | awk -F '"' '{print $4}')

  echo -e "${CYAN}${INDENT}===== 当前 SSR 配置 =====${NC}"
  echo -e "${INDENT}🌐 服务器   : ${YELLOW}$ip${NC}"
  echo -e "${INDENT}🔌 端口     : ${YELLOW}$PORT${NC}"
  echo -e "${INDENT}🔑 密码     : ${YELLOW}$PASSWORD${NC}"
  echo -e "${INDENT}🔒 加密方式 : ${YELLOW}$METHOD${NC}"
  echo -e "${INDENT}📜 协议     : ${YELLOW}$PROTOCOL${NC}"
  echo -e "${INDENT}🎭 混淆     : ${YELLOW}$OBFS${NC}"
  echo -e "${CYAN}${INDENT}=========================${NC}"
  generate_ssr_link
}

# ========== 功能 ==========
install_ssr() {
  echo -e "${BLUE}${INDENT}安装 SSR...${NC}"
  read -p "${INDENT}请输入端口 [默认20000]: " PORT
  PORT=${PORT:-20000}
  read -p "${INDENT}请输入密码 [默认dongtaiwang.com]: " PASSWORD
  PASSWORD=${PASSWORD:-dongtaiwang.com}
  choose_method
  choose_protocol
  choose_obfs

  install_docker

  docker pull $DOCKER_IMAGE
  docker stop $CONTAINER_NAME >/dev/null 2>&1
  docker rm $CONTAINER_NAME >/dev/null 2>&1
  docker run -dit --name $CONTAINER_NAME --restart unless-stopped -p ${PORT}:${PORT} $DOCKER_IMAGE

  set_config
  # 确保容器已就绪
  sleep 1
  docker exec -d $CONTAINER_NAME python /usr/local/shadowsocks/server.py -c $CONFIG_PATH -d start
  echo -e "${GREEN}${INDENT}✅ SSR 安装完成${NC}"
  show_config
}

change_config() {
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo -e "${RED}${INDENT}未检测到 SSR 容器，请先安装${NC}"
    return
  fi

  echo -e "${BLUE}${INDENT}修改 SSR 配置...${NC}"

  if docker exec "$CONTAINER_NAME" test -f "$CONFIG_PATH"; then
    local cfg=$(docker exec -i $CONTAINER_NAME cat $CONFIG_PATH 2>/dev/null)
    PORT=$(echo "$cfg" | grep '"server_port"' | awk -F ':' '{print $2}' | tr -d ' ,')
    PASSWORD=$(echo "$cfg" | grep '"password"' | awk -F '"' '{print $4}')
    METHOD=$(echo "$cfg" | grep '"method"' | awk -F '"' '{print $4}')
    PROTOCOL=$(echo "$cfg" | grep '"protocol"' | awk -F '"' '{print $4}')
    OBFS=$(echo "$cfg" | grep '"obfs"' | awk -F '"' '{print $4}')
  fi

  read -p "${INDENT}新端口 (回车保留: ${PORT:-20000}): " NEW_PORT
  read -p "${INDENT}新密码 (回车保留: ${PASSWORD:-dongtaiwang.com}): " NEW_PASSWORD
  choose_method
  choose_protocol
  choose_obfs

  NEW_PORT=${NEW_PORT:-$PORT}
  PASSWORD=${NEW_PASSWORD:-$PASSWORD}

  if [ "$NEW_PORT" != "$PORT" ] && [ -n "$NEW_PORT" ]; then
    echo -e "${YELLOW}${INDENT}端口改变，重新创建容器...${NC}"
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    docker run -dit --name $CONTAINER_NAME --restart unless-stopped -p ${NEW_PORT}:${NEW_PORT} $DOCKER_IMAGE
    sleep 1
  fi

  PORT=${NEW_PORT:-$PORT}
  set_config
  docker exec -d $CONTAINER_NAME python /usr/local/shadowsocks/server.py -c $CONFIG_PATH -d restart
  sleep 1
  echo -e "${GREEN}${INDENT}✅ 配置修改完成${NC}"
  show_config
}

start_ssr() {
  # 容器存在？
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo -e "${RED}${INDENT}未检测到 SSR 容器，请先执行『安装 SSR』${NC}"
    return
  fi

  # 容器未运行则先启动容器
  if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" != "true" ]; then
    if ! docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
      echo -e "${RED}${INDENT}容器无法启动，请查看日志： docker logs ${CONTAINER_NAME}${NC}"
      return
    fi
    sleep 1
  fi

  # 配置文件存在？
  if ! docker exec "$CONTAINER_NAME" test -f "$CONFIG_PATH"; then
    echo -e "${YELLOW}${INDENT}未发现配置文件，请先『安装 SSR』或『修改配置』写入参数${NC}"
    return
  fi

  docker exec -d "$CONTAINER_NAME" python /usr/local/shadowsocks/server.py -c "$CONFIG_PATH" -d start
  sleep 1
  if docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1; then
    echo -e "${GREEN}${INDENT}✅ SSR 已启动${NC}"
  else
    echo -e "${RED}${INDENT}❌ SSR 启动失败，最近日志如下：${NC}"
    docker logs --tail 80 "$CONTAINER_NAME" 2>&1 | sed "s/^/${INDENT}/"
  fi
}

stop_ssr() {
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"
    return
  fi

  if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" = "true" ]; then
    docker exec -d "$CONTAINER_NAME" python /usr/local/shadowsocks/server.py -c "$CONFIG_PATH" -d stop
    sleep 1
  fi

  if docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1; then
    echo -e "${RED}${INDENT}❌ SSR 停止失败${NC}"
  else
    echo -e "${YELLOW}${INDENT}🛑 SSR 已停止${NC}"
  fi
}

restart_ssr() {
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"
    return
  fi

  if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" != "true" ]; then
    docker start "$CONTAINER_NAME" >/dev/null 2>&1 || {
      echo -e "${RED}${INDENT}容器无法启动，请查看日志： docker logs ${CONTAINER_NAME}${NC}"
      return
    }
    sleep 1
  fi

  if ! docker exec "$CONTAINER_NAME" test -f "$CONFIG_PATH"; then
    echo -e "${YELLOW}${INDENT}未发现配置文件，请先『安装 SSR』或『修改配置』写入参数${NC}"
    return
  fi

  docker exec -d "$CONTAINER_NAME" python /usr/local/shadowsocks/server.py -c "$CONFIG_PATH" -d restart
  sleep 1
  if docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1; then
    echo -e "${GREEN}${INDENT}🔄 SSR 已重启${NC}"
  else
    echo -e "${RED}${INDENT}❌ SSR 重启失败，最近日志如下：${NC}"
    docker logs --tail 80 "$CONTAINER_NAME" 2>&1 | sed "s/^/${INDENT}/"
  fi
}

uninstall_ssr() {
  echo -e "${RED}${INDENT}卸载 SSR...${NC}"
  docker stop $CONTAINER_NAME >/dev/null 2>&1
  docker rm $CONTAINER_NAME >/dev/null 2>&1
  docker rmi $DOCKER_IMAGE >/dev/null 2>&1
  # 仅删除容器内配置文件；宿主机无持久化路径则无需额外处理
  echo -e "${RED}${INDENT}✅ SSR 已卸载完成${NC}"
}

# ========== 系统加速 ==========
optimize_system() {
  echo -e "${BLUE}${INDENT}检查系统加速状态...${NC}"
  local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

  if [[ "$cc" == "bbr" && "$qdisc" == "fq" ]]; then
    echo -e "${GREEN}${INDENT}✅ 系统加速已启用 (BBR + TFO)${NC}"
  else
    echo -e "${YELLOW}${INDENT}正在启用 TCP Fast Open + BBR...${NC}"
    {
      echo "net.ipv4.tcp_fastopen = 3"
      echo "net.core.default_qdisc = fq"
      echo "net.ipv4.tcp_congestion_control = bbr"
    } >> /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [[ "$cc" == "bbr" && "$qdisc" == "fq" ]]; then
      echo -e "${GREEN}${INDENT}✅ 系统加速已成功启用 (BBR + TCP Fast Open)${NC}"
    else
      echo -e "${RED}${INDENT}⚠️ 设置完成，但未检测到 BBR 启动，可能内核不支持 (>= 4.9)${NC}"
    fi
  fi
}

# ========== 主菜单 ==========
check_bbr
check_ssr_status

echo -e "${CYAN}${INDENT}=============================="
echo -e "${INDENT}🚀 SSR-Plus 管理脚本 ${VERSION} 🚀"
echo -e "${INDENT}脚本更新地址:https://github.com/Alvin9999/SSR-Plus"
echo -e "${INDENT}==============================${NC}"
echo -e "${GREEN}${INDENT}1) 安装 SSR${NC}"
echo -e "${GREEN}${INDENT}2) 修改配置${NC}"
echo -e "${GREEN}${INDENT}3) 查看配置${NC}"
echo -e "${GREEN}${INDENT}4) 启动 SSR${NC}"
echo -e "${GREEN}${INDENT}5) 停止 SSR${NC}"
echo -e "${GREEN}${INDENT}6) 重启 SSR${NC}"
echo -e "${YELLOW}${INDENT}7) 卸载 SSR${NC}"
echo -e "${BLUE}${INDENT}8) 启用系统加速 (BBR + TFO)${NC}"
echo -e "${RED}${INDENT}9) 退出${NC}"
echo -e "${CYAN}${INDENT}==============================${NC}"
echo -e "${INDENT}系统加速状态: ${BBR_STATUS}"
echo -e "${INDENT}SSR 当前状态: ${SSR_STATUS}"
echo -e "${CYAN}${INDENT}==============================${NC}"

read -p "${INDENT}请输入选项 [1-9]: " choice
case $choice in
  1) install_docker; install_ssr ;;
  2) change_config ;;
  3) show_config ;;
  4) start_ssr ;;
  5) stop_ssr ;;
  6) restart_ssr ;;
  7) uninstall_ssr ;;
  8) optimize_system ;;
  9) exit 0 ;;
  *) echo -e "${RED}${INDENT}无效选项${NC}";;
esac
