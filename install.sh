#!/bin/bash
# ==========================================================
# LNMP 一键安装脚本 v1.0
# Linux + Nginx + MariaDB + PHP
#
# 支持系统: Ubuntu / Debian / CentOS / RHEL / Rocky / Alma
# PHP 版本: 7.2 / 7.3 / 7.4 / 8.0 / 8.1 / 8.2
# 数据库:   MariaDB 10.11 (轻量替代 MySQL)
# SSL:      acme.sh + Let's Encrypt
# 优化:     512MB 小内存 VPS 专项优化
#
# 用法: chmod +x install.sh && ./install.sh
# ==========================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 加载模块
source "${SCRIPT_DIR}/include/common.sh"
source "${SCRIPT_DIR}/include/nginx.sh"
source "${SCRIPT_DIR}/include/mariadb.sh"
source "${SCRIPT_DIR}/include/php.sh"
source "${SCRIPT_DIR}/include/ssl.sh"

# 安装信息保存路径
INSTALL_INFO="/usr/local/nginx/conf/.lnmp_install_info"

show_system_info() {
    print_separator
    echo -e "${BOLD}系统信息:${NC}"
    echo -e "  系统:   ${OS_NAME}"
    echo -e "  内存:   $(get_mem_mb) MB"
    echo -e "  CPU:    $(get_cpu_cores) 核"
    echo -e "  IP:     $(get_ip)"
    print_separator
}

select_db_password() {
    echo ""
    echo -en "${BOLD}设置 MariaDB root 密码 (留空自动生成): ${NC}"
    read -rs db_pass_input
    echo ""
    if [ -n "$db_pass_input" ]; then
        DB_ROOT_PASS="$db_pass_input"
    else
        DB_ROOT_PASS=$(gen_random_password)
        print_info "已自动生成数据库 root 密码"
    fi
}

show_install_plan() {
    echo ""
    print_separator
    echo -e "${BOLD}即将安装以下组件:${NC}"
    echo -e "  - Nginx          (官方最新稳定版)"
    echo -e "  - MariaDB        ${MARIADB_VERSION} (LTS)"
    echo -e "  - PHP            ${PHP_VER}"
    echo -e "  - acme.sh        (SSL 证书管理)"
    echo ""
    echo -e "${BOLD}内存优化:${NC}"
    local mem_mb
    mem_mb=$(get_mem_mb)
    if [ "$mem_mb" -le 512 ]; then
        echo -e "  - 创建 1GB 交换分区"
        echo -e "  - PHP-FPM ondemand 模式 (最大 5 进程)"
        echo -e "  - MariaDB InnoDB 缓冲池 64MB"
        echo -e "  - Nginx worker_connections 512"
    elif [ "$mem_mb" -le 1024 ]; then
        echo -e "  - PHP-FPM ondemand 模式 (最大 10 进程)"
        echo -e "  - MariaDB InnoDB 缓冲池 128MB"
        echo -e "  - Nginx worker_connections 1024"
    else
        echo -e "  - PHP-FPM ondemand 模式 (最大 20 进程)"
        echo -e "  - MariaDB InnoDB 缓冲池 256MB"
        echo -e "  - Nginx worker_connections 2048"
    fi
    print_separator
    echo ""
}

save_install_info() {
    cat > "$INSTALL_INFO" <<INFO
# LNMP 安装信息 - $(date '+%Y-%m-%d %H:%M:%S')
NGINX_VERSION=$(nginx -v 2>&1 | awk -F/ '{print $2}')
MARIADB_VERSION=${MARIADB_VERSION}
PHP_VERSION=${PHP_VER}
DB_ROOT_PASS=${DB_ROOT_PASS}
WEBROOT=/home/wwwroot
LOGDIR=/home/wwwlogs
VHOST_DIR=/usr/local/nginx/conf/vhost
SSL_DIR=/usr/local/nginx/conf/ssl
SERVER_IP=$(get_ip)
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
INFO
    chmod 600 "$INSTALL_INFO"
}

print_install_summary() {
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           LNMP 安装完成！                       ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local server_ip
    server_ip=$(get_ip)

    echo -e "${BOLD}访问地址:${NC}"
    echo -e "  http://${server_ip}/"
    echo ""
    echo -e "${BOLD}安装信息:${NC}"
    echo -e "  Nginx:    $(nginx -v 2>&1 | awk -F/ '{print $2}')"
    echo -e "  MariaDB:  ${MARIADB_VERSION}"
    echo -e "  PHP:      ${PHP_VER}"
    echo ""
    echo -e "${BOLD}MariaDB:${NC}"
    echo -e "  用户名:   root"
    echo -e "  密码:     ${YELLOW}${DB_ROOT_PASS}${NC}"
    echo ""
    echo -e "${BOLD}重要路径:${NC}"
    echo -e "  站点目录:  /home/wwwroot/"
    echo -e "  日志目录:  /home/wwwlogs/"
    echo -e "  虚拟主机:  /usr/local/nginx/conf/vhost/"
    echo -e "  Nginx配置: /etc/nginx/nginx.conf"
    echo ""
    echo -e "${BOLD}管理命令:${NC}"
    echo -e "  lnmp start|stop|restart     启动/停止/重启"
    echo -e "  lnmp status                 查看服务状态"
    echo -e "  lnmp vhost add              添加虚拟主机"
    echo -e "  lnmp vhost del              删除虚拟主机"
    echo -e "  lnmp vhost list             列出虚拟主机"
    echo -e "  lnmp ssl add <域名>         申请 SSL 证书"
    echo -e "  lnmp info                   查看安装信息"
    echo ""
    print_separator
    echo -e "${RED}请妥善保存以上信息，特别是数据库密码！${NC}"
    echo -e "安装信息已保存至: ${INSTALL_INFO}"
    print_separator
}

# =========================
# 主流程
# =========================

main() {
    print_banner
    check_root
    detect_os
    show_system_info

    # 交互选择
    select_php_version
    select_db_password
    setup_ssl  # 输入邮箱

    # 确认安装
    show_install_plan
    if ! confirm_continue "确认开始安装？"; then
        print_warn "安装已取消"
        exit 0
    fi

    local start_time
    start_time=$(date +%s)

    echo ""
    print_info "========== 开始安装 =========="
    echo ""

    # Step 1: 基础准备
    print_info "[1/6] 安装基础依赖..."
    install_base_deps
    create_www_user
    create_dirs

    # Step 2: 配置交换分区
    print_info "[2/6] 配置交换分区..."
    setup_swap

    # Step 3: 安装 Nginx
    print_info "[3/6] 安装 Nginx..."
    setup_nginx

    # Step 4: 安装 MariaDB
    print_info "[4/6] 安装 MariaDB..."
    setup_mariadb

    # Step 5: 安装 PHP
    print_info "[5/6] 安装 PHP ${PHP_VER}..."
    add_php_repo
    install_php
    configure_php_fpm
    start_php_fpm

    # Step 6: 安装 SSL 工具
    print_info "[6/6] 安装 SSL 证书工具..."
    install_acme

    # 启动 Nginx
    systemctl enable nginx
    systemctl start nginx

    # 安装管理脚本
    if [ -f "${SCRIPT_DIR}/lnmp" ]; then
        cp "${SCRIPT_DIR}/lnmp" /usr/local/bin/lnmp
        chmod +x /usr/local/bin/lnmp
        print_ok "管理脚本已安装到 /usr/local/bin/lnmp"
    fi

    # 保存安装信息
    save_install_info

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))

    echo ""
    print_ok "安装总耗时: $((elapsed / 60)) 分 $((elapsed % 60)) 秒"

    # 打印摘要
    print_install_summary
}

main "$@"
