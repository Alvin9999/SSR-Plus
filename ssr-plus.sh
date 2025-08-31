#!/bin/bash
# 🚀 SSR-Plus Docker 管理脚本
# 支持 Debian/Ubuntu/CentOS/RHEL/Rocky/AlmaLinux/Fedora/openSUSE
# 版本号: v1.1.9

stty erase ^H   # 让退格键在终端里正常工作

DOCKER_IMAGE="yinqishuo/ssr:0.01"
CONTAINER_NAME="ssr"
CONFIG_PATH="/etc/shadowsocks-r/config.json"

# ========== 样式 ==========
RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; CYAN='\e[36m'; NC='\e[0m'
INDENT=" "
VERSION="v1.1.9"

# ========== 更新源（可配镜像/IPv4/IPv6/强制覆盖）==========
RAW_URL_DEFAULT="https://raw.githubusercontent.com/Alvin9999/SSR-Plus/main/ssr-plus.sh"

# 获取当前脚本的真实路径（便于原地覆盖）
script_path() {
  local p
  p="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || realpath "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "$0")"
  if [[ ! -f "$p" || "$(basename "$p")" = "bash" ]]; then
    [[ -f "./ssr-plus.sh" ]] && p="./ssr-plus.sh" || { echo ""; return 1; }
  fi
  echo "$p"
}

# 用 curl 或 wget 下载到指定文件（支持 SSRPLUS_IPMODE=4/6、SSRPLUS_MIRROR）
fetch_to() {
  local url="$1" out="$2" opts=()
  [[ "$SSRPLUS_IPMODE" = "4" ]] && opts+=(-4)
  [[ "$SSRPLUS_IPMODE" = "6" ]] && opts+=(-6)
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${opts[@]}" "$url" -o "$out"
  else
    wget -q "${opts[@]}" -O "$out" "$url"
  fi
}

# ========== 系统检测 ==========
detect_os(){ if [ -f /etc/os-release ]; then . /etc/os-release; OS=$ID; else OS=$(uname -s); fi; }

# ========== Docker 安装 ==========
install_docker(){
  detect_os
  echo -e "${BLUE}${INDENT}[1/4] 安装 Docker... 系统: $OS${NC}"
  case "$OS" in
    ubuntu|debian)
      apt-get update -y
      apt-get install -y ca-certificates curl gnupg lsb-release
      mkdir -p /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list >/dev/null
      apt-get update -y
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    centos|rhel)
      yum install -y yum-utils device-mapper-persistent-data lvm2 || {
        echo -e "${RED}${INDENT}❌ yum-utils 安装失败，请先: yum clean all && rm -rf /var/cache/yum${NC}"; exit 1; }
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      yum install -y docker-ce docker-ce-cli containerd.io || {
        echo -e "${RED}${INDENT}❌ Docker 安装失败，请检查网络/源${NC}"; exit 1; }
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
  command -v docker >/dev/null 2>&1 || { echo -e "${RED}${INDENT}❌ Docker 未安装成功${NC}"; exit 1; }
  systemctl enable docker >/dev/null 2>&1
  systemctl start docker
}

# ========== 确保 Docker 运行 ==========
ensure_docker_running(){ command -v docker >/dev/null 2>&1 || return 1; docker info >/dev/null 2>&1 || systemctl start docker; docker info >/dev/null 2>&1; }

# ========== 状态检测 ==========
check_ssr_status(){
  if ! command -v docker >/dev/null 2>&1; then SSR_STATUS="${RED}未安装 (Docker 未安装)${NC}"; return; fi
  docker info >/dev/null 2>&1 || { SSR_STATUS="${RED}Docker 未运行${NC}"; return; }
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" || { SSR_STATUS="${RED}未安装${NC}"; return; }
  [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" = "true" ] || { SSR_STATUS="${YELLOW}容器已停止${NC}"; return; }
  if docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1; then
    SSR_STATUS="${GREEN}已启动${NC}"
  else
    SSR_STATUS="${YELLOW}容器运行中 (SSR 进程未运行)${NC}"
  fi
}

# ========== BBR 检测 ==========
check_bbr(){
  local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
  [[ "$cc" == "bbr" && "$qdisc" == "fq" ]] && BBR_STATUS="${GREEN}已启用 BBR${NC}" || BBR_STATUS="${RED}未启用 BBR${NC}"
}

# ========== 选择项 ==========
choose_method(){ echo -e "\n${CYAN}${INDENT}请选择加密方式:${NC}"
  cat <<EOF
 ${INDENT}1) none
 ${INDENT}2) rc4
 ${INDENT}3) rc4-md5
 ${INDENT}4) rc4-md5-6
 ${INDENT}5) aes-128-ctr
 ${INDENT}6) aes-192-ctr
 ${INDENT}7) aes-256-ctr
 ${INDENT}8) aes-128-cfb
 ${INDENT}9) aes-192-cfb
 ${INDENT}10) aes-256-cfb
 ${INDENT}11) aes-128-cfb8
 ${INDENT}12) aes-192-cfb8
 ${INDENT}13) aes-256-cfb8
 ${INDENT}14) salsa20
 ${INDENT}15) chacha20
 ${INDENT}16) chacha20-ietf
EOF
  read -p "${INDENT}输入序号 [默认16]: " method
  case $method in
    1) METHOD="none";; 2) METHOD="rc4";; 3) METHOD="rc4-md5";; 4) METHOD="rc4-md5-6";;
    5) METHOD="aes-128-ctr";; 6) METHOD="aes-192-ctr";; 7) METHOD="aes-256-ctr";;
    8) METHOD="aes-128-cfb";; 9) METHOD="aes-192-cfb";; 10) METHOD="aes-256-cfb";;
    11) METHOD="aes-128-cfb8";; 12) METHOD="aes-192-cfb8";; 13) METHOD="aes-256-cfb8";;
    14) METHOD="salsa20";; 15) METHOD="chacha20";; 16|"") METHOD="chacha20-ietf";; *) METHOD="chacha20-ietf";;
  esac
}
choose_protocol(){ echo -e "\n${CYAN}${INDENT}请选择协议 (protocol):${NC}"
  cat <<EOF
 ${INDENT}1) origin
 ${INDENT}2) auth_sha1_v4
 ${INDENT}3) auth_aes128_md5
 ${INDENT}4) auth_aes128_sha1
 ${INDENT}5) auth_chain_a
 ${INDENT}6) auth_chain_b
EOF
  read -p "${INDENT}输入序号 [默认2]: " protocol
  case $protocol in
    1) PROTOCOL="origin";; 2|"") PROTOCOL="auth_sha1_v4";; 3) PROTOCOL="auth_aes128_md5";;
    4) PROTOCOL="auth_aes128_sha1";; 5) PROTOCOL="auth_chain_a";; 6) PROTOCOL="auth_chain_b";; *) PROTOCOL="auth_sha1_v4";;
  esac
}
choose_obfs(){ echo -e "\n${CYAN}${INDENT}请选择混淆 (obfs):${NC}"
  cat <<EOF
 ${INDENT}1) plain
 ${INDENT}2) http_simple
 ${INDENT}3) http_post
 ${INDENT}4) random_head
 ${INDENT}5) tls1.2_ticket_auth
EOF
  read -p "${INDENT}输入序号 [默认1]: " obfs
  case $obfs in
    1|"") OBFS="plain";; 2) OBFS="http_simple";; 3) OBFS="http_post";; 4) OBFS="random_head";; 5) OBFS="tls1.2_ticket_auth";; *) OBFS="plain";;
  esac
}

# ========== 配置（原子写入） ==========
set_config(){
  docker exec -i $CONTAINER_NAME bash -lc "umask 077; mkdir -p /etc/shadowsocks-r && cat > ${CONFIG_PATH}.tmp && mv -f ${CONFIG_PATH}.tmp ${CONFIG_PATH} && sync" <<EOF
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

generate_ssr_link(){
  local ip=$(curl -s ifconfig.me)
  local pass_b64=$(echo -n "${PASSWORD}" | base64 -w0)
  local raw="${ip}:${PORT}:${PROTOCOL}:${METHOD}:${OBFS}:${pass_b64}/"
  echo -e "\n${GREEN}${INDENT}SSR 链接:${NC}\n${INDENT}ssr://$(echo -n "$raw" | base64 -w0)\n"
}

show_config(){
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo -e "${RED}${INDENT}Docker 未运行${NC}"; return; }
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" || { echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"; return; }
  docker exec "$CONTAINER_NAME" test -f "$CONFIG_PATH" || { echo -e "${YELLOW}${INDENT}容器内未找到配置文件${NC}"; return; }
  local cfg=$(docker exec -i $CONTAINER_NAME cat $CONFIG_PATH 2>/dev/null); local ip=$(curl -s ifconfig.me)
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

# ========== 启动等待 & 重试 ==========
start_ssr_and_wait(){
  docker exec -d "$CONTAINER_NAME" python /usr/local/shadowsocks/server.py -c "$CONFIG_PATH" -d start
  for i in {1..5}; do sleep 1; docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1 && { echo -e "${GREEN}${INDENT}✅ SSR 已启动${NC}"; return 0; }; done
  docker exec -d "$CONTAINER_NAME" python /usr/local/shadowsocks/server.py -c "$CONFIG_PATH" -d start
  sleep 1; docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1 && { echo -e "${GREEN}${INDENT}✅ SSR 已启动${NC}"; return 0; }
  echo -e "${RED}${INDENT}❌ SSR 启动失败，最近日志：${NC}"; docker logs --tail 80 "$CONTAINER_NAME" 2>&1 | sed "s/^/${INDENT}/"; return 1
}

# ========== 生成容器（带自启守护脚本） ==========
run_container_with_boot(){
  local map_port="$1"
  docker run -dit --name $CONTAINER_NAME \
    --restart unless-stopped \
    -p ${map_port}:${map_port} \
    --health-cmd "python -c 'import socket,sys; s=socket.socket(); s.settimeout(2); s.connect((\"127.0.0.1\",${map_port})); s.close()' || exit 1" \
    --health-interval 10s --health-retries 3 --health-timeout 3s --health-start-period 5s \
    $DOCKER_IMAGE \
    bash -lc 'cat >/usr/local/bin/ssr-boot.sh << "SH"
#!/bin/bash
CFG="/etc/shadowsocks-r/config.json"
# 等待配置文件写入
for i in {1..60}; do [ -f "$CFG" ] && break; sleep 1; done
sleep 2
pgrep -f server.py >/dev/null 2>&1 || python /usr/local/shadowsocks/server.py -c "$CFG" -d start
while sleep 5; do
  pgrep -f server.py >/dev/null 2>&1 || python /usr/local/shadowsocks/server.py -c "$CFG" -d start
done
SH
chmod +x /usr/local/bin/ssr-boot.sh
exec /usr/local/bin/ssr-boot.sh'
}

# ========== 功能 ==========
install_ssr(){
  echo -e "${BLUE}${INDENT}安装 SSR...${NC}"
  read -p "${INDENT}请输入端口 [默认20000]: " PORT; PORT=${PORT:-20000}
  read -p "${INDENT}请输入密码 [默认dongtaiwang.com]: " PASSWORD; PASSWORD=${PASSWORD:-dongtaiwang.com}
  choose_method; choose_protocol; choose_obfs

  install_docker; ensure_docker_running || { echo -e "${RED}${INDENT}Docker 未运行，安装中止${NC}"; return; }
  docker pull $DOCKER_IMAGE
  docker stop $CONTAINER_NAME >/dev/null 2>&1; docker rm $CONTAINER_NAME >/dev/null 2>&1

  run_container_with_boot "${PORT}"
  sleep 1
  set_config
  start_ssr_and_wait
  echo -e "${GREEN}${INDENT}✅ SSR 安装完成${NC}"
  show_config
}

change_config(){
  ensure_docker_running || { echo -e "${RED}${INDENT}Docker 未运行${NC}"; return; }
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" || { echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"; return; }

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
  choose_method; choose_protocol; choose_obfs
  NEW_PORT=${NEW_PORT:-$PORT}; PASSWORD=${NEW_PASSWORD:-$PASSWORD}

  if [ "$NEW_PORT" != "$PORT" ] && [ -n "$NEW_PORT" ]; then
    echo -e "${YELLOW}${INDENT}端口改变，重新创建容器...${NC}"
    docker stop $CONTAINER_NAME >/dev/null 2>&1; docker rm $CONTAINER_NAME >/dev/null 2>&1
    run_container_with_boot "${NEW_PORT}"
    sleep 1
  fi

  PORT=${NEW_PORT:-$PORT}
  set_config
  docker exec -d $CONTAINER_NAME python /usr/local/shadowsocks/server.py -c $CONFIG_PATH -d stop >/dev/null 2>&1
  sleep 1
  start_ssr_and_wait
  echo -e "${GREEN}${INDENT}✅ 配置修改完成${NC}"
  show_config
}

start_ssr(){
  ensure_docker_running || { echo -e "${RED}${INDENT}Docker 未运行${NC}"; return; }
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" || { echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"; return; }
  [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" = "true" ] || docker start "$CONTAINER_NAME" >/dev/null 2>&1
  docker exec "$CONTAINER_NAME" test -f "$CONFIG_PATH" || { echo -e "${YELLOW}${INDENT}未发现配置文件${NC}"; return; }
  start_ssr_and_wait
}

stop_ssr(){
  ensure_docker_running || { echo -e "${RED}${INDENT}Docker 未运行${NC}"; return; }
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" || { echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"; return; }
  [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" = "true" ] && docker exec -d "$CONTAINER_NAME" python /usr/local/shadowsocks/server.py -c "$CONFIG_PATH" -d stop
  sleep 1
  docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1 && echo -e "${RED}${INDENT}❌ SSR 停止失败${NC}" || echo -e "${YELLOW}${INDENT}🛑 SSR 已停止${NC}"
}

restart_ssr(){
  ensure_docker_running || { echo -e "${RED}${INDENT}Docker 未运行${NC}"; return; }
  docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" || { echo -e "${RED}${INDENT}未检测到 SSR 容器${NC}"; return; }
  [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" = "true" ] || docker start "$CONTAINER_NAME" >/dev/null 2>&1
  docker exec "$CONTAINER_NAME" test -f "$CONFIG_PATH" || { echo -e "${YELLOW}${INDENT}未发现配置文件${NC}"; return; }
  docker exec -d "$CONTAINER_NAME" python /usr/local/shadowsocks/server.py -c "$CONFIG_PATH" -d stop
  sleep 1; start_ssr_and_wait; echo -e "${GREEN}${INDENT}🔄 SSR 已重启${NC}"
}

uninstall_ssr(){
  echo -e "${RED}${INDENT}卸载 SSR...${NC}"
  if command -v docker >/dev/null 2>&1; then docker stop $CONTAINER_NAME >/dev/null 2>&1; docker rm $CONTAINER_NAME >/dev/null 2>&1; docker rmi $DOCKER_IMAGE >/dev/null 2>&1; fi
  echo -e "${RED}${INDENT}✅ SSR 已卸载完成${NC}"
}

# ========== 系统加速 ==========
optimize_system(){
  echo -e "${BLUE}${INDENT}检查系统加速状态...${NC}"
  local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null); local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
  if [[ "$cc" == "bbr" && "$qdisc" == "fq" ]]; then
    echo -e "${GREEN}${INDENT}✅ 系统加速已启用 (BBR + TFO)${NC}"
  else
    echo -e "${YELLOW}${INDENT}正在启用 TCP Fast Open + BBR...${NC}"
    { echo "net.ipv4.tcp_fastopen = 3"; echo "net.core.default_qdisc = fq"; echo "net.ipv4.tcp_congestion_control = bbr"; } >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null); qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    [[ "$cc" == "bbr" && "$qdisc" == "fq" ]] && echo -e "${GREEN}${INDENT}✅ 系统加速已成功启用 (BBR + TCP Fast Open)${NC}" \
                                            || echo -e "${RED}${INDENT}⚠️ 内核可能不支持 BBR (>=4.9)${NC}"
  fi
}

# ========== 自愈（保留） ==========
auto_heal_ssr(){
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || return
  docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$" || return
  docker exec "$CONTAINER_NAME" pgrep -f "server.py" >/dev/null 2>&1 && return
  echo -e "${YELLOW}${INDENT}检测到 SSR 未运行，尝试自动拉起...${NC}"
  start_ssr_and_wait
}

# ========== 脚本自更新（含版本判断/镜像/强制） ==========
update_script() {
  echo -e "${BLUE}${INDENT}检查脚本更新...${NC}"
  local raw="${RAW_URL_DEFAULT}"
  [[ -n "$SSRPLUS_MIRROR" ]] && raw="${SSRPLUS_MIRROR}${RAW_URL_DEFAULT}"

  local tmp="$(mktemp)"
  if ! fetch_to "$raw" "$tmp"; then
    echo -e "${RED}${INDENT}❌ 下载失败。${NC}"
    echo -e "${YELLOW}${INDENT}可设置镜像： export SSRPLUS_MIRROR='https://ghproxy.com/'${NC}"
    echo -e "${YELLOW}${INDENT}切换 IPv4/IPv6： export SSRPLUS_IPMODE=4  或  6${NC}"
    rm -f "$tmp"; return 1
  fi
  if ! grep -q "SSR-Plus Docker 管理脚本" "$tmp"; then
    echo -e "${RED}${INDENT}❌ 下载内容异常，已取消更新${NC}"; rm -f "$tmp"; return 1
  fi

  local self; self="$(script_path)"
  if [[ -z "$self" ]]; then
    echo -e "${RED}${INDENT}❌ 无法定位当前脚本路径，请在脚本所在目录执行更新${NC}"
    rm -f "$tmp"; return 1
  fi

  local local_ver remote_ver
  local_ver="$(grep -E 'VERSION="' "$self" 2>/dev/null | head -n1 | sed -E 's/.*VERSION="([^"]+)".*/\1/')"
  remote_ver="$(grep -E 'VERSION="' "$tmp"  2>/dev/null | head -n1 | sed -E 's/.*VERSION="([^"]+)".*/\1/')"
  [[ -z "$local_ver" ]] && local_ver="v0.0.0"
  [[ -z "$remote_ver" ]] && { echo -e "${RED}${INDENT}❌ 未能解析远端版本号，已取消更新${NC}"; rm -f "$tmp"; return 1; }

  local lv rv max; lv="${local_ver#v}"; rv="${remote_ver#v}"
  max="$(printf '%s\n%s\n' "$lv" "$rv" | sort -V | tail -n1)"

  if [[ "$lv" = "$rv" && "$SSRPLUS_FORCE" != "1" ]]; then
    echo -e "${GREEN}${INDENT}✅ 已是最新版：${local_ver}${NC}"
    rm -f "$tmp"; return 0
  fi
  if [[ "$max" = "$lv" && "$lv" != "$rv" && "$SSRPLUS_FORCE" != "1" ]]; then
    echo -e "${YELLOW}${INDENT}ℹ️ 本地版本 (${local_ver}) 新于远端 (${remote_ver})，跳过更新${NC}"
    rm -f "$tmp"; return 0
  fi

  cp -f "$self" "$self.bak-$(date +%F-%H%M%S)" 2>/dev/null
  chmod +x "$tmp" && mv -f "$tmp" "$self"
  echo -e "${GREEN}${INDENT}✅ 更新完成： ${local_ver} → ${remote_ver}${NC}"
  echo -e "${INDENT}正在重新加载新版本..."
  exec bash "$self"
}

# ========== 主菜单 ==========
check_bbr
ensure_docker_running >/dev/null 2>&1
check_ssr_status
auto_heal_ssr
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
echo -e "${BLUE}${INDENT}9) 检查并更新脚本${NC}"
echo -e "${RED}${INDENT}10) 退出${NC}"
echo -e "${CYAN}${INDENT}==============================${NC}"
echo -e "${INDENT}系统加速状态: ${BBR_STATUS}"
echo -e "${INDENT}SSR 当前状态: ${SSR_STATUS}"
echo -e "${CYAN}${INDENT}==============================${NC}"

read -p "${INDENT}请输入选项 [1-10]: " choice
case $choice in
  1) install_docker; install_ssr ;;
  2) change_config ;;
  3) show_config ;;
  4) start_ssr ;;
  5) stop_ssr ;;
  6) restart_ssr ;;
  7) uninstall_ssr ;;
  8) optimize_system ;;
  9) update_script ;;
  10) exit 0 ;;
  *) echo -e "${RED}${INDENT}无效选项${NC}";;
esac
