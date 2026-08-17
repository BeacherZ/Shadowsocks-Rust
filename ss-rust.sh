#!/bin/bash

# ====================================================================
# Shadowsocks-Rust 服务管理脚本
# 支持系统: Debian 10+ / Ubuntu 18.04+ / Alpine 3.12+ / CentOS 7+ ...
# ====================================================================

# 1. 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31m[ERROR] 此脚本必须以 root 权限运行！请使用 sudo -i 切换到 root 用户后重试。\033[0m"
    exit 1
fi

CONF_DIR="/etc/shadowsocks-rust"
CONF_FILE="${CONF_DIR}/config.json"
SYSTEMD_FILE="/etc/systemd/system/shadowsocks-rust.service"
OPENRC_FILE="/etc/init.d/shadowsocks-rust"
BIN_PATH="/usr/local/bin/ssserver"

# 自动适配包管理器安装依赖
install_dependencies() {
    echo "[STEP] 正在检查并安装所需依赖包..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl tar xz-utils jq >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1
        apk add --no-cache curl tar xz jq bash >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl tar xz jq >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release >/dev/null 2>&1
        yum install -y curl tar xz jq >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm curl tar xz jq >/dev/null 2>&1
    else
        echo -e "\033[33m[WARN] 未找到常见的包管理器，请确保已手动安装 curl, tar, xz, jq\033[0m"
    fi
}

# 判断服务是否在运行 (兼容 Systemd 和 OpenRC)
is_service_running() {
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet shadowsocks-rust 2>/dev/null; then
        return 0
    elif command -v rc-service >/dev/null 2>&1 && rc-service shadowsocks-rust status 2>/dev/null | grep -q "started"; then
        return 0
    elif pgrep -f "$BIN_PATH" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# 启动服务通用接口
start_service_cmd() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start shadowsocks-rust
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service shadowsocks-rust start
    elif [[ -x "$OPENRC_FILE" ]]; then
        "$OPENRC_FILE" start
    fi
}

# 停止服务通用接口
stop_service_cmd() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop shadowsocks-rust
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service shadowsocks-rust stop
    elif [[ -x "$OPENRC_FILE" ]]; then
        "$OPENRC_FILE" stop
    fi
}

# 获取已安装版本号
get_installed_version() {
    if [[ -f "$BIN_PATH" ]]; then
        local ver
        ver=$($BIN_PATH --version 2>/dev/null | awk '{print $2}')
        [[ -n "$ver" && "$ver" != v* ]] && ver="v${ver}"
        echo "${ver:-未知}"
    else
        echo ""
    fi
}

# 动态获取并解析该版本支持的所有加密算法（强制将 aes-128-gcm 置顶于第一位）
get_supported_methods() {
    local raw_methods
    # 从 ssserver --help 的 possible values 中提取支持的加密方式
    raw_methods=$($BIN_PATH --help 2>&1 | tr '\n' ' ' | grep -oE "possible values: [^]]+" | sed 's/possible values: //; s/,/ /g')
    
    # 兜底备用算法集
    if [[ -z "$raw_methods" ]]; then
        raw_methods="aes-128-gcm aes-256-gcm chacha20-ietf-poly1305 2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm 2022-blake3-chacha20-poly1305 aes-192-gcm sm4-gcm"
    fi

    local method_list=()
    method_list+=("aes-128-gcm") # 强制第一位为 aes-128-gcm

    for m in $raw_methods; do
        m=$(echo "$m" | xargs)
        # 过滤非加密/不常用模式及已在首位的 aes-128-gcm
        [[ -z "$m" || "$m" == "none" || "$m" == "plain" || "$m" == "aes-128-gcm" ]] && continue
        method_list+=("$m")
    done

    echo "${method_list[@]}"
}

# 打印菜单状态行
print_status_line() {
    if [[ ! -f "$BIN_PATH" ]]; then
        local status_text="\033[31m未安装\033[0m"
        printf "║  服务状态: %b%43s ║\n" "$status_text" ""
        return
    fi

    local ver_str
    ver_str=$(get_installed_version)

    local status_text=""
    if is_service_running; then
        status_text="\033[32m● 运行中\033[0m"
    else
        status_text="\033[31m● 已停止\033[0m"
    fi

    local pad_len=$((21 - ${#ver_str}))
    (( pad_len < 0 )) && pad_len=0

    printf "║  服务状态: %b (Shadowsocks-rust-%s)%*s ║\n" "$status_text" "$ver_str" "$pad_len" ""
}

# 1. 安装 Shadowsocks-Rust
install_ss() {
    echo -e "\n══════════════════════════════════════════════════════════════"
    echo "         安装 Shadowsocks-Rust 服务端"
    echo -e "══════════════════════════════════════════════════════════════"
    
    install_dependencies

    echo "[STEP] 正在自动检索系统架构..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)   SS_ARCH="x86_64-unknown-linux-musl" ;;
        aarch64|arm64)  SS_ARCH="aarch64-unknown-linux-musl" ;;
        armv7l|armhf)   SS_ARCH="armv7-unknown-linux-musleabihf" ;;
        i386|i686)      SS_ARCH="i686-unknown-linux-musl" ;;
        *) echo -e "\033[31m[ERROR] 暂不支持的架构: $ARCH\033[0m"; return ;;
    esac
    echo "[INFO] 检测到架构: $ARCH (优先采用 Musl 静态编译包)"

    echo "[STEP] 正在检索版本列表并逐个测试是否支持 aes-128-gcm..."
    RELEASES=$(curl -s --max-time 10 https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases?per_page=30 | jq -r '.[].tag_name' 2>/dev/null)
    
    if [[ -z "$RELEASES" || "$RELEASES" == "null" ]]; then
        RELEASES="v1.22.0 v1.21.2 v1.20.4 v1.19.0 v1.18.0 v1.17.0"
    fi

    FOUND_VER=""
    for VER in $RELEASES; do
        echo " ├─ 正在核验版本: $VER ..."
        URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${VER}/shadowsocks-${VER}.${SS_ARCH}.tar.xz"
        
        curl -L -s --max-time 20 -o /tmp/ss-rust.tar.xz "$URL"
        if [[ $? -ne 0 || ! -s /tmp/ss-rust.tar.xz ]]; then
            echo " │  └─ [SKIP] 下载失败或此版本缺少该架构包，清除并跳过..."
            rm -f /tmp/ss-rust.tar.xz
            continue
        fi

        tar -xf /tmp/ss-rust.tar.xz -C /tmp/ ssserver 2>/dev/null
        if [[ -f "/tmp/ssserver" ]]; then
            chmod +x /tmp/ssserver
            if /tmp/ssserver --help 2>&1 | grep -qi "aes-128-gcm"; then
                echo -e " │  └─ \033[32m[MATCH] 校验通过！版本 $VER 完美支持 aes-128-gcm！\033[0m"
                FOUND_VER="$VER"
                mv /tmp/ssserver "$BIN_PATH"
                rm -f /tmp/ss*
                break
            else
                echo -e " │  └─ \033[33m[UNSUPPORTED] 版本 $VER 不支持 aes-128-gcm，立即清理并测试上一版本...\033[0m"
                rm -f /tmp/ssserver /tmp/ss-rust.tar.xz
            fi
        else
            echo " │  └─ [SKIP] 解压失败，清除并跳过..."
            rm -f /tmp/ss-rust.tar.xz
        fi
    done

    if [[ -z "$FOUND_VER" ]]; then
        echo -e "\033[31m[ERROR] 未能在 Release 列表中找到任何支持 aes-128-gcm 的版本！\033[0m"
        return
    fi

    echo -e "\n──────────────────────────────────────────────────────────────"
    echo "  交互设置 (已部署 Shadowsocks-Rust $FOUND_VER)"
    echo "──────────────────────────────────────────────────────────────"
    
    read -p "  输入服务端口 [1-65535] (默认: 33962): " PORT
    PORT=${PORT:-33962}

    RAND_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    read -p "  输入连接密码 (默认随机生成): " PASSWORD
    PASSWORD=${PASSWORD:-$RAND_PASS}

    # 动态解析此版本支持的所有加密算法
    METHODS=($(get_supported_methods))

    echo -e "\n  选择加密方式 (当前版本共支持 ${#METHODS[@]} 种):"
    local idx=1
    for m in "${METHODS[@]}"; do
        if [[ "$m" == "aes-128-gcm" ]]; then
            echo "    ${idx}) ${m} (推荐，老旧客户端完美兼容)"
        else
            echo "    ${idx}) ${m}"
        fi
        ((idx++))
    done

    read -p "  请选择 [1-${#METHODS[@]}] (默认: 1): " METHOD_CHOICE
    METHOD_CHOICE=${METHOD_CHOICE:-1}

    if [[ "$METHOD_CHOICE" -ge 1 && "$METHOD_CHOICE" -le "${#METHODS[@]}" ]]; then
        METHOD="${METHODS[$((METHOD_CHOICE-1))]}"
    else
        METHOD="aes-128-gcm"
    fi

    echo -e "\n  选择传输模式:"
    echo "    1) TCP + UDP (推荐)"
    echo "    2) 仅 TCP"
    echo "    3) 仅 UDP"
    read -p "  请选择 [1-3] (默认: 1): " MODE_CHOICE
    case "$MODE_CHOICE" in
        2) MODE="tcp_only" ;;
        3) MODE="udp_only" ;;
        *) MODE="tcp_and_udp" ;;
    esac

    echo "[STEP] 生成配置文件..."
    mkdir -p "$CONF_DIR"
    
    cat <<EOF > "$CONF_FILE"
{
    "server": "::",
    "server_port": $PORT,
    "password": "$PASSWORD",
    "method": "$METHOD",
    "mode": "$MODE",
    "fast_open": false
}
EOF
    chmod 600 "$CONF_FILE"

    echo "[STEP] 配置系统自启服务..."
    if command -v systemctl >/dev/null 2>&1; then
        cat <<EOF > "$SYSTEMD_FILE"
[Unit]
Description=Shadowsocks-Rust Server
After=network.target

[Service]
Type=simple
User=root
Group=root
LimitNOFILE=512000
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable shadowsocks-rust >/dev/null 2>&1
    elif command -v rc-update >/dev/null 2>&1; then
        cat <<EOF > "$OPENRC_FILE"
#!/sbin/openrc-run
name="Shadowsocks-Rust Server"
description="Shadowsocks-Rust Service"
command="/usr/local/bin/ssserver"
command_args="-c /etc/shadowsocks-rust/config.json"
command_background="yes"
pidfile="/run/shadowsocks-rust.pid"

depend() {
    need net
    after firewall
}
EOF
        chmod +x "$OPENRC_FILE"
        rc-update add shadowsocks-rust default >/dev/null 2>&1
    fi

    echo "[STEP] 启动 Shadowsocks-Rust 服务..."
    start_service_cmd

    if is_service_running; then
        echo -e "\033[32m[SUCCESS] Shadowsocks-Rust 安装并启动成功！\033[0m"
        show_config
    else
        echo -e "\033[31m[ERROR] 服务启动失败，请选择菜单 [8] 查看运行日志。\033[0m"
    fi
}

# 2. 更新 Shadowsocks-Rust
update_ss() {
    if [[ ! -f "$BIN_PATH" ]]; then
        echo -e "\033[31m[ERROR] 未检测到已安装的 Shadowsocks-Rust！\033[0m"
        return
    fi
    echo "[STEP] 检查更新..."
    LATEST_VER=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | jq -r .tag_name)
    CURRENT_VER=$(get_installed_version)
    
    echo "当前版本: $CURRENT_VER"
    echo "最新版本: $LATEST_VER"
    
    if [[ "$CURRENT_VER" == "$LATEST_VER" ]]; then
        echo -e "\033[32m当前已经是最新版本！\033[0m"
        return
    fi
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)   SS_ARCH="x86_64-unknown-linux-musl" ;;
        aarch64|arm64)  SS_ARCH="aarch64-unknown-linux-musl" ;;
        armv7l|armhf)   SS_ARCH="armv7-unknown-linux-musleabihf" ;;
        i386|i686)      SS_ARCH="i686-unknown-linux-musl" ;;
        *) echo -e "\033[31m[ERROR] 暂不支持的架构: $ARCH\033[0m"; return ;;
    esac

    URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_VER}/shadowsocks-${LATEST_VER}.${SS_ARCH}.tar.xz"
    
    echo "[STEP] 下载新版本..."
    curl -L -o /tmp/ss-rust.tar.xz "$URL"
    stop_service_cmd
    tar -xf /tmp/ss-rust.tar.xz -C /tmp/
    mv /tmp/ssserver "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -f /tmp/ss*
    start_service_cmd
    echo -e "\033[32m[SUCCESS] 更新完成，当前版本: $(get_installed_version)\033[0m"
}

# 3. 卸载 Shadowsocks-Rust
uninstall_ss() {
    read -p "确定要彻底卸载 Shadowsocks-Rust 吗？[y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        stop_service_cmd
        if command -v systemctl >/dev/null 2>&1; then
            systemctl disable shadowsocks-rust >/dev/null 2>&1
            rm -f "$SYSTEMD_FILE"
            systemctl daemon-reload
        elif command -v rc-update >/dev/null 2>&1; then
            rc-update del shadowsocks-rust default >/dev/null 2>&1
            rm -f "$OPENRC_FILE"
        fi
        rm -f "$BIN_PATH"
        rm -rf "$CONF_DIR"
        echo -e "\033[32m[SUCCESS] Shadowsocks-Rust 卸载完成。\033[0m"
    fi
}

# 4. 启动服务
start_ss() {
    if [[ ! -f "$BIN_PATH" ]]; then
        echo -e "\033[31m未安装 Shadowsocks-Rust，请先进行安装！\033[0m"
        return
    fi
    start_service_cmd
    if is_service_running; then
        echo -e "\033[32m服务启动成功！\033[0m"
    else
        echo -e "\033[31m服务启动失败，请检查日志！\033[0m"
    fi
}

# 5. 停止服务
stop_ss() {
    if [[ ! -f "$BIN_PATH" ]]; then
        echo -e "\033[31m未安装 Shadowsocks-Rust！\033[0m"
        return
    fi
    stop_service_cmd
    echo -e "\033[33m服务已停止。\033[0m"
}

# 6. 重启服务
restart_ss() {
    if [[ ! -f "$BIN_PATH" ]]; then
        echo -e "\033[31m未安装 Shadowsocks-Rust！\033[0m"
        return
    fi
    stop_service_cmd
    sleep 1
    start_service_cmd
    if is_service_running; then
        echo -e "\033[32m服务重启成功！\033[0m"
    else
        echo -e "\033[31m服务重启失败，请检查日志！\033[0m"
    fi
}

# 7. 查看配置及 SS 链接
show_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        echo -e "\033[31m配置文件不存在或未安装！\033[0m"
        return
    fi
    
    PORT=$(jq -r .server_port "$CONF_FILE")
    PASSWORD=$(jq -r .password "$CONF_FILE")
    METHOD=$(jq -r .method "$CONF_FILE")
    
    # 获取 IPv4 与 IPv6 (3 秒超时检测)
    IPV4=$(curl -s4 --max-time 3 https://api.ipify.org 2>/dev/null || curl -s4 --max-time 3 https://icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    IPV6=$(curl -s6 --max-time 3 https://api64.ipify.org 2>/dev/null || curl -s6 --max-time 3 https://icanhazip.com 2>/dev/null)

    # 生成 IPv4 SS 链接
    RAW_SS_V4="${METHOD}:${PASSWORD}@${IPV4}:${PORT}"
    ENCODED_SS_V4=$(echo -n "$RAW_SS_V4" | base64 -w0 2>/dev/null || echo -n "$RAW_SS_V4" | base64 | tr -d '\n')
    SS_LINK_V4="ss://${ENCODED_SS_V4}#Shadowsocks-Rust"

    echo -e "\n──────────────────────────────────────────────────────────────"
    echo "  Shadowsocks-Rust 配置信息"
    echo "──────────────────────────────────────────────────────────────"
    echo "  配置文件路径 : $CONF_FILE"
    echo "  服务器 IPv4  : $IPV4"
    if [[ -n "$IPV6" ]]; then
        echo "  服务器 IPv6  : $IPV6"
    else
        echo "  服务器 IPv6  : 当前服务器无 IPv6"
    fi
    echo "  服务端口     : $PORT"
    echo "  连接密码     : $PASSWORD"
    echo "  加密方式     : $METHOD"
    echo "──────────────────────────────────────────────────────────────"
    echo "  SS 链接 (IPv4) : $SS_LINK_V4"
    if [[ -n "$IPV6" ]]; then
        RAW_SS_V6="${METHOD}:${PASSWORD}@[${IPV6}]:${PORT}"
        ENCODED_SS_V6=$(echo -n "$RAW_SS_V6" | base64 -w0 2>/dev/null || echo -n "$RAW_SS_V6" | base64 | tr -d '\n')
        SS_LINK_V6="ss://${ENCODED_SS_V6}#Shadowsocks-Rust-IPv6"
        echo "  SS 链接 (IPv6) : $SS_LINK_V6"
    fi
    echo -e "──────────────────────────────────────────────────────────────\n"
}

# 8. 查看运行日志
view_logs() {
    echo -e "\033[36m正在查看运行日志 (按 Ctrl+C 退出)... \033[0m\n"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u shadowsocks-rust -n 50 -f
    elif [[ -f "/var/log/messages" ]]; then
        tail -f -n 50 /var/log/messages
    else
        echo -e "\033[33m未检测到 journalctl 或常见日志文件，请通过 systemctl 或 rc-service 检查。 \033[0m"
    fi
}

# 菜单主循环
main_menu() {
    while true; do
        clear
        echo -e "╔══════════════════════════════════════════════════════════════╗"
        echo -e "║                Shadowsocks-Rust 服务管理脚本                 ║"
        echo -e "╠══════════════════════════════════════════════════════════════╣"
        print_status_line
        echo -e "╠══════════════════════════════════════════════════════════════╣"
        echo -e "║  1. 安装 Shadowsocks-Rust                                    ║"
        echo -e "║  2. 更新 Shadowsocks-Rust                                    ║"
        echo -e "║  3. 卸载 Shadowsocks-Rust                                    ║"
        echo -e "╟──────────────────────────────────────────────────────────────╢"
        echo -e "║  4. 启动服务                                                 ║"
        echo -e "║  5. 停止服务                                                 ║"
        echo -e "║  6. 重启服务                                                 ║"
        echo -e "╟──────────────────────────────────────────────────────────────╢"
        echo -e "║  7. 查看配置及 SS 链接 (IPv4 / IPv6)                         ║"
        echo -e "║  8. 查看运行日志                                             ║"
        echo -e "║  0. 退出脚本                                                 ║"
        echo -e "╚══════════════════════════════════════════════════════════════╝"
        
        read -p " 请选择操作 [0-8]: " CHOICE
        case "$CHOICE" in
            1) install_ss ;;
            2) update_ss ;;
            3) uninstall_ss ;;
            4) start_ss ;;
            5) stop_ss ;;
            6) restart_ss ;;
            7) show_config ;;
            8) view_logs ;;
            0) exit 0 ;;
            *) echo -e "\033[31m无效选项，请输入 0-8\033[0m" ;;
        esac
        echo ""
        read -p "按 Enter 键返回主菜单..."
    done
}

main_menu