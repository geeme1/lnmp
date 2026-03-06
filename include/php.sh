#!/bin/bash
# ==========================================================
# LNMP 一键安装脚本 - PHP 安装模块
# 支持 PHP 7.2 - 8.2 版本选择
# 支持交互式选择 PHP 扩展
# Debian/Ubuntu 使用 Ondřej Surý PPA
# CentOS/RHEL 使用 Remi 仓库
# ==========================================================

PHP_VERSIONS=("7.2" "7.3" "7.4" "8.0" "8.1" "8.2")
PHP_EOL_VERSIONS=("7.2" "7.3" "7.4" "8.0")

# 扩展分类：名称:描述:是否默认选中(1/0)
EXT_BASE=(
    "fpm:PHP-FPM 进程管理器:1:必装"
    "cli:命令行接口:1:必装"
    "common:公共文件:1:必装"
    "mysql:MySQL/MariaDB 支持:1:必装"
    "mysqlnd:MySQL 原生驱动:1:必装"
    "opcache:OPcache 字节码缓存:1:必装"
)

EXT_COMMON=(
    "curl:cURL 网络请求:1"
    "gd:图像处理 (GD):1"
    "mbstring:多字节字符串:1"
    "xml:XML 解析:1"
    "zip:ZIP 压缩:1"
    "bcmath:高精度数学:1"
    "intl:国际化支持:1"
    "soap:SOAP Web 服务:0"
)

EXT_EXTRA=(
    "redis:Redis 缓存:0"
    "memcached:Memcached 缓存:0"
    "imagick:ImageMagick 图像处理:0"
    "sqlite3:SQLite3 数据库:0"
    "pgsql:PostgreSQL 数据库:0"
    "ldap:LDAP 目录服务:0"
    "imap:IMAP 邮件:0"
    "gmp:GNU 多精度算术:0"
    "bz2:Bzip2 压缩:0"
    "exif:图片 EXIF 信息:0"
    "fileinfo:文件类型检测:1"
    "sockets:Socket 网络:0"
    "xdebug:调试工具 (生产环境慎用):0"
)

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

select_php_extensions() {
    echo ""
    print_separator
    echo -e "${BOLD}选择 PHP 扩展:${NC}"
    echo ""

    # 基础扩展 (强制安装，不可取消)
    echo -e "  ${BOLD}[基础扩展 - 自动安装]${NC}"
    for item in "${EXT_BASE[@]}"; do
        local name desc
        name=$(echo "$item" | cut -d: -f1)
        desc=$(echo "$item" | cut -d: -f2)
        echo -e "    ${GREEN}*${NC} ${name}  ${CYAN}- ${desc}${NC}"
    done

    # 常用扩展 (可选)
    echo ""
    echo -e "  ${BOLD}[常用扩展]${NC}"
    local all_optional=()
    local all_selected=()
    local idx=1

    for item in "${EXT_COMMON[@]}"; do
        local name desc default_on mark
        name=$(echo "$item" | cut -d: -f1)
        desc=$(echo "$item" | cut -d: -f2)
        default_on=$(echo "$item" | cut -d: -f3)
        all_optional+=("$name")
        all_selected+=("$default_on")
        if [ "$default_on" = "1" ]; then
            mark="${GREEN}*${NC}"
        else
            mark=" "
        fi
        printf "    ${mark} ${CYAN}%-3s${NC} %-15s ${CYAN}- %s${NC}\n" "${idx})" "$name" "$desc"
        ((idx++))
    done

    # 额外扩展 (可选)
    echo ""
    echo -e "  ${BOLD}[额外扩展]${NC}"
    for item in "${EXT_EXTRA[@]}"; do
        local name desc default_on mark
        name=$(echo "$item" | cut -d: -f1)
        desc=$(echo "$item" | cut -d: -f2)
        default_on=$(echo "$item" | cut -d: -f3)
        all_optional+=("$name")
        all_selected+=("$default_on")
        if [ "$default_on" = "1" ]; then
            mark="${GREEN}*${NC}"
        else
            mark=" "
        fi
        printf "    ${mark} ${CYAN}%-3s${NC} %-15s ${CYAN}- %s${NC}\n" "${idx})" "$name" "$desc"
        ((idx++))
    done

    local total=${#all_optional[@]}
    echo ""
    echo -e "  ${GREEN}*${NC} 表示默认选中"
    echo ""
    echo -e "${BOLD}操作说明:${NC}"
    echo -e "  直接回车  = 使用默认选择 (带 * 的)"
    echo -e "  输入序号  = 切换选中状态 (用空格或逗号分隔多个)"
    echo -e "  输入 ${CYAN}all${NC}  = 全选"
    echo -e "  输入 ${CYAN}none${NC} = 只装基础扩展"
    echo ""

    while true; do
        echo -en "${BOLD}请输入 (直接回车使用默认): ${NC}"
        read -r ext_input

        if [ -z "$ext_input" ]; then
            break
        elif [ "$ext_input" = "all" ]; then
            for i in "${!all_selected[@]}"; do
                all_selected[$i]="1"
            done
            print_ok "已全选所有扩展"
            break
        elif [ "$ext_input" = "none" ]; then
            for i in "${!all_selected[@]}"; do
                all_selected[$i]="0"
            done
            print_ok "仅安装基础扩展"
            break
        else
            # 解析逗号或空格分隔的序号
            local nums
            nums=$(echo "$ext_input" | tr ',' ' ')
            for num in $nums; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$total" ]; then
                    local arr_idx=$((num - 1))
                    if [ "${all_selected[$arr_idx]}" = "1" ]; then
                        all_selected[$arr_idx]="0"
                        print_info "取消: ${all_optional[$arr_idx]}"
                    else
                        all_selected[$arr_idx]="1"
                        print_info "选中: ${all_optional[$arr_idx]}"
                    fi
                else
                    print_warn "无效序号: $num"
                fi
            done
            echo -en "${BOLD}继续修改或直接回车确认: ${NC}"
            read -r more_input
            if [ -z "$more_input" ]; then
                break
            fi
            ext_input="$more_input"
            nums=$(echo "$ext_input" | tr ',' ' ')
            for num in $nums; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$total" ]; then
                    local arr_idx=$((num - 1))
                    if [ "${all_selected[$arr_idx]}" = "1" ]; then
                        all_selected[$arr_idx]="0"
                        print_info "取消: ${all_optional[$arr_idx]}"
                    else
                        all_selected[$arr_idx]="1"
                        print_info "选中: ${all_optional[$arr_idx]}"
                    fi
                fi
            done
            break
        fi
    done

    # 构建最终选中的扩展列表
    SELECTED_EXTENSIONS=()
    for i in "${!all_optional[@]}"; do
        if [ "${all_selected[$i]}" = "1" ]; then
            SELECTED_EXTENSIONS+=("${all_optional[$i]}")
        fi
    done

    echo ""
    print_info "将要安装的扩展: ${SELECTED_EXTENSIONS[*]}"
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

get_php_pkg_name() {
    local ext_name="$1"
    local php_prefix
    case "$PKG_MGR" in
        apt) php_prefix="php${PHP_VER}" ;;
        yum|dnf) php_prefix="php" ;;
    esac
    echo "${php_prefix}-${ext_name}"
}

install_php() {
    print_info "安装 PHP ${PHP_VER}..."
    pkg_update

    local php_prefix
    case "$PKG_MGR" in
        apt) php_prefix="php${PHP_VER}" ;;
        yum|dnf) php_prefix="php" ;;
    esac

    # 基础扩展 (必装)
    local packages=(
        "${php_prefix}-fpm"
        "${php_prefix}-cli"
        "${php_prefix}-common"
        "${php_prefix}-mysql"
        "${php_prefix}-mysqlnd"
        "${php_prefix}-opcache"
    )

    # Debian/Ubuntu 额外装 mysqli
    if [ "$PKG_MGR" = "apt" ]; then
        packages+=("${php_prefix}-mysqli")
    fi

    # json 扩展在 PHP 8.0+ 已内置
    local ver_major="${PHP_VER%%.*}"
    if [ "$ver_major" -lt 8 ]; then
        packages+=("${php_prefix}-json")
    fi

    # 用户选择的扩展
    if [ ${#SELECTED_EXTENSIONS[@]} -gt 0 ]; then
        for ext in "${SELECTED_EXTENSIONS[@]}"; do
            packages+=("${php_prefix}-${ext}")
        done
    fi

    print_info "安装 ${#packages[@]} 个包..."
    pkg_install "${packages[@]}" 2>/dev/null

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

    # 显示已安装的扩展
    echo ""
    print_info "已加载的扩展:"
    $php_bin -m 2>/dev/null | grep -v '^\[' | sort | tr '\n' ', ' | sed 's/,$/\n/'
    echo ""
}

# 单独安装扩展 (安装后使用)
install_php_extension() {
    local ext_name="$1"
    local php_ver

    if [ -f /usr/local/nginx/conf/.php_version ]; then
        php_ver=$(cat /usr/local/nginx/conf/.php_version)
    else
        php_ver=$(php -v 2>/dev/null | head -1 | grep -oP '\d+\.\d+' | head -1)
    fi

    if [ -z "$php_ver" ]; then
        print_error "无法检测 PHP 版本"
        return 1
    fi

    if [ -z "$ext_name" ]; then
        print_error "请指定扩展名称"
        return 1
    fi

    # 检测包管理器
    local pkg_mgr_local php_prefix
    if command -v apt-get &>/dev/null; then
        pkg_mgr_local="apt"
        php_prefix="php${php_ver}"
    elif command -v dnf &>/dev/null; then
        pkg_mgr_local="dnf"
        php_prefix="php"
    elif command -v yum &>/dev/null; then
        pkg_mgr_local="yum"
        php_prefix="php"
    fi

    local pkg="${php_prefix}-${ext_name}"
    print_info "安装 PHP 扩展: ${pkg}..."

    case "$pkg_mgr_local" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
        dnf) dnf install -y "$pkg" ;;
        yum) yum install -y "$pkg" ;;
    esac

    if [ $? -eq 0 ]; then
        # 重启 PHP-FPM
        local fpm_svc
        if [ -f /usr/local/nginx/conf/.php_fpm_service ]; then
            fpm_svc=$(cat /usr/local/nginx/conf/.php_fpm_service)
        else
            fpm_svc="php${php_ver}-fpm"
        fi
        systemctl restart "$fpm_svc" 2>/dev/null
        print_ok "扩展 ${ext_name} 安装成功，PHP-FPM 已重启"
    else
        print_error "扩展 ${ext_name} 安装失败"
    fi
}

# 列出已安装的 PHP 扩展
list_php_extensions() {
    local php_bin
    if [ -f /usr/local/nginx/conf/.php_version ]; then
        local php_ver
        php_ver=$(cat /usr/local/nginx/conf/.php_version)
        php_bin="php${php_ver}"
    fi

    if ! command -v "$php_bin" &>/dev/null; then
        php_bin="php"
    fi

    echo ""
    echo -e "${BOLD}已安装的 PHP 扩展:${NC}"
    echo ""
    $php_bin -m 2>/dev/null | grep -v '^\[' | sort | while read -r ext; do
        [ -n "$ext" ] && echo -e "  ${GREEN}*${NC} ${ext}"
    done
    echo ""
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
    select_php_extensions
    add_php_repo
    install_php
    configure_php_fpm
    start_php_fpm
}
