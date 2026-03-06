#!/bin/bash
# ==========================================================
# LNMP 一键安装脚本 - PHP 安装模块
# 支持 PHP 7.2 - 8.2 版本选择
# Debian/Ubuntu 使用 Ondřej Surý PPA
# CentOS/RHEL 使用 Remi 仓库
# ==========================================================

PHP_VERSIONS=("7.2" "7.3" "7.4" "8.0" "8.1" "8.2")
PHP_EOL_VERSIONS=("7.2" "7.3" "7.4" "8.0")

select_php_version() {
    echo ""
    print_separator
    echo -e "${BOLD}请选择 PHP 版本:${NC}"
    echo ""
    local i=1
    for v in "${PHP_VERSIONS[@]}"; do
        local eol_mark=""
        for ev in "${PHP_EOL_VERSIONS[@]}"; do
            if [ "$v" = "$ev" ]; then
                eol_mark=" ${YELLOW}(已停止官方支持)${NC}"
                break
            fi
        done
        echo -e "  ${CYAN}${i})${NC} PHP ${v}${eol_mark}"
        ((i++))
    done
    echo ""

    local choice
    while true; do
        echo -en "${BOLD}请输入序号 [1-${#PHP_VERSIONS[@]}] (默认 6 即 PHP 8.2): ${NC}"
        read -r choice
        choice=${choice:-6}
        if [[ "$choice" =~ ^[1-6]$ ]]; then
            PHP_VER="${PHP_VERSIONS[$((choice-1))]}"
            break
        fi
        print_warn "无效选择，请重新输入"
    done

    print_info "已选择 PHP ${PHP_VER}"
}

add_php_repo() {
    print_info "添加 PHP ${PHP_VER} 软件源..."
    case "$OS_ID" in
        ubuntu)
            pkg_install software-properties-common
            add-apt-repository -y ppa:ondrej/php
            ;;
        debian)
            pkg_install lsb-release ca-certificates curl
            curl -fsSL https://packages.sury.org/php/apt.gpg \
                | gpg --dearmor -o /usr/share/keyrings/php-sury-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/php-sury-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -cs) main" \
                > /etc/apt/sources.list.d/php-sury.list
            ;;
        centos|rhel|rocky|almalinux)
            pkg_install https://rpms.remirepo.net/enterprise/remi-release-${OS_MAJOR_VERSION}.rpm 2>/dev/null
            if command -v dnf &>/dev/null; then
                dnf module reset php -y 2>/dev/null
                dnf module enable php:remi-${PHP_VER} -y 2>/dev/null
            fi
            ;;
        fedora)
            pkg_install https://rpms.remirepo.net/fedora/remi-release-${OS_MAJOR_VERSION}.rpm 2>/dev/null
            dnf module reset php -y 2>/dev/null
            dnf module enable php:remi-${PHP_VER} -y 2>/dev/null
            ;;
    esac
    print_ok "PHP 软件源添加完成"
}

install_php() {
    print_info "安装 PHP ${PHP_VER} 及常用扩展..."
    pkg_update

    local php_prefix
    case "$PKG_MGR" in
        apt) php_prefix="php${PHP_VER}" ;;
        yum|dnf) php_prefix="php" ;;
    esac

    local extensions=(
        "${php_prefix}-fpm"
        "${php_prefix}-cli"
        "${php_prefix}-common"
        "${php_prefix}-curl"
        "${php_prefix}-gd"
        "${php_prefix}-mbstring"
        "${php_prefix}-xml"
        "${php_prefix}-zip"
        "${php_prefix}-opcache"
        "${php_prefix}-bcmath"
        "${php_prefix}-intl"
        "${php_prefix}-soap"
        "${php_prefix}-mysql"
    )

    # mysqlnd / mysqli
    case "$PKG_MGR" in
        apt)
            extensions+=("${php_prefix}-mysqlnd")
            extensions+=("${php_prefix}-mysqli")
            ;;
        yum|dnf)
            extensions+=("${php_prefix}-mysqlnd")
            ;;
    esac

    # json 扩展在 PHP 8.0+ 已内置
    local ver_major="${PHP_VER%%.*}"
    local ver_minor="${PHP_VER##*.}"
    if [ "$ver_major" -lt 8 ]; then
        extensions+=("${php_prefix}-json")
    fi

    pkg_install "${extensions[@]}" 2>/dev/null

    # 验证安装
    local php_bin
    case "$PKG_MGR" in
        apt) php_bin="php${PHP_VER}" ;;
        yum|dnf) php_bin="php" ;;
    esac

    if ! command -v "$php_bin" &>/dev/null; then
        if command -v php &>/dev/null; then
            php_bin="php"
        else
            print_error "PHP 安装失败"
            exit 1
        fi
    fi

    local php_actual_ver
    php_actual_ver=$($php_bin -v | head -1)
    print_ok "PHP 安装完成: $php_actual_ver"
}

configure_php_fpm() {
    print_info "优化 PHP-FPM 配置 (小内存模式)..."

    local mem_mb max_children
    mem_mb=$(get_mem_mb)

    if [ "$mem_mb" -le 512 ]; then
        max_children=5
    elif [ "$mem_mb" -le 1024 ]; then
        max_children=10
    else
        max_children=20
    fi

    # 查找 PHP-FPM 池配置文件路径
    local pool_conf=""
    local fpm_sock="/run/php-fpm/www.sock"
    local fpm_service=""

    case "$PKG_MGR" in
        apt)
            pool_conf="/etc/php/${PHP_VER}/fpm/pool.d/www.conf"
            fpm_sock="/run/php/php${PHP_VER}-fpm.sock"
            fpm_service="php${PHP_VER}-fpm"
            ;;
        yum|dnf)
            pool_conf="/etc/php-fpm.d/www.conf"
            fpm_sock="/run/php-fpm/www.sock"
            fpm_service="php-fpm"
            mkdir -p /run/php-fpm
            ;;
    esac

    if [ -f "$pool_conf" ]; then
        cp "$pool_conf" "${pool_conf}.bak"
    fi

    cat > "$pool_conf" <<FPM_CONF
[www]
user = www
group = www

listen = ${fpm_sock}
listen.owner = www
listen.group = www
listen.mode = 0660

; 使用 ondemand 模式，空闲时不占用内存
pm = ondemand
pm.max_children = ${max_children}
pm.process_idle_timeout = 10s
pm.max_requests = 500

; 状态页
pm.status_path = /fpm-status

; 慢日志
slowlog = /home/wwwlogs/php-fpm-slow.log
request_slowlog_timeout = 5s

; 错误日志
php_admin_value[error_log] = /home/wwwlogs/php-fpm-error.log
php_admin_flag[log_errors] = on
FPM_CONF

    # 优化 php.ini
    local php_ini=""
    case "$PKG_MGR" in
        apt) php_ini="/etc/php/${PHP_VER}/fpm/php.ini" ;;
        yum|dnf) php_ini="/etc/php.ini" ;;
    esac

    if [ -f "$php_ini" ]; then
        cp "$php_ini" "${php_ini}.bak"

        # 安全 & 性能设置
        sed -i 's/^expose_php.*/expose_php = Off/' "$php_ini"
        sed -i 's/^upload_max_filesize.*/upload_max_filesize = 50M/' "$php_ini"
        sed -i 's/^post_max_size.*/post_max_size = 50M/' "$php_ini"
        sed -i 's/^max_execution_time.*/max_execution_time = 300/' "$php_ini"
        sed -i 's/^max_input_time.*/max_input_time = 300/' "$php_ini"
        sed -i 's/^memory_limit.*/memory_limit = 128M/' "$php_ini"
        sed -i 's/^;date.timezone.*/date.timezone = Asia\/Shanghai/' "$php_ini"
        sed -i 's/^disable_functions.*/disable_functions = passthru,exec,system,chroot,chgrp,chown,popen,proc_open,ini_alter,ini_restore,dl,openlog,syslog,popepassthru,pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals/' "$php_ini"
    fi

    # OPcache 配置
    local opcache_ini=""
    if [ -d "/etc/php/${PHP_VER}/fpm/conf.d" ]; then
        opcache_ini="/etc/php/${PHP_VER}/fpm/conf.d/99-opcache-lnmp.ini"
    elif [ -d "/etc/php.d" ]; then
        opcache_ini="/etc/php.d/99-opcache-lnmp.ini"
    fi

    if [ -n "$opcache_ini" ]; then
        cat > "$opcache_ini" <<'OPCACHE'
[opcache]
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=64
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
OPCACHE
    fi

    # 更新 Nginx 中的 PHP-FPM socket 路径
    if [ "$PKG_MGR" = "apt" ]; then
        sed -i "s|unix:/run/php-fpm/www.sock|unix:${fpm_sock}|g" /etc/nginx/nginx.conf
    fi

    # 保存 FPM 服务名供后续使用
    echo "$fpm_service" > /usr/local/nginx/conf/.php_fpm_service
    echo "$fpm_sock" > /usr/local/nginx/conf/.php_fpm_sock
    echo "$PHP_VER" > /usr/local/nginx/conf/.php_version

    print_ok "PHP-FPM 配置优化完成"
}

start_php_fpm() {
    local fpm_service
    fpm_service=$(cat /usr/local/nginx/conf/.php_fpm_service 2>/dev/null)

    if [ -z "$fpm_service" ]; then
        case "$PKG_MGR" in
            apt) fpm_service="php${PHP_VER}-fpm" ;;
            yum|dnf) fpm_service="php-fpm" ;;
        esac
    fi

    systemctl enable "$fpm_service"
    systemctl start "$fpm_service"
    print_ok "PHP-FPM 服务已启动"
}

setup_php() {
    select_php_version
    add_php_repo
    install_php
    configure_php_fpm
    start_php_fpm
}
