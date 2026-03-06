#!/bin/bash
# ==========================================================
# LNMP 一键安装脚本 - MariaDB 安装模块
# 使用 MariaDB 替代 MySQL，更轻量适合小内存 VPS
# ==========================================================

MARIADB_VERSION="10.11"

add_mariadb_repo() {
    print_info "添加 MariaDB ${MARIADB_VERSION} 官方源..."
    case "$OS_ID" in
        ubuntu|debian)
            pkg_install apt-transport-https curl
            curl -fsSL "https://mariadb.org/mariadb_release_signing_key.pgp" \
                | gpg --dearmor -o /usr/share/keyrings/mariadb-archive-keyring.gpg

            local codename
            codename=$(lsb_release -cs)

            cat > /etc/apt/sources.list.d/mariadb.list <<REPO
deb [signed-by=/usr/share/keyrings/mariadb-archive-keyring.gpg] https://dlm.mariadb.com/repo/mariadb-server/${MARIADB_VERSION}/repo/${OS_ID} ${codename} main
REPO
            ;;
        centos|rhel|rocky|almalinux)
            cat > /etc/yum.repos.d/mariadb.repo <<REPO
[mariadb]
name=MariaDB ${MARIADB_VERSION}
baseurl=https://dlm.mariadb.com/repo/mariadb-server/${MARIADB_VERSION}/yum/rhel/\$releasever/\$basearch
gpgkey=https://mariadb.org/mariadb_release_signing_key.pgp
gpgcheck=1
enabled=1
module_hotfixes=true
REPO
            ;;
        fedora)
            cat > /etc/yum.repos.d/mariadb.repo <<REPO
[mariadb]
name=MariaDB ${MARIADB_VERSION}
baseurl=https://dlm.mariadb.com/repo/mariadb-server/${MARIADB_VERSION}/yum/fedora/\$releasever/\$basearch
gpgkey=https://mariadb.org/mariadb_release_signing_key.pgp
gpgcheck=1
enabled=1
REPO
            ;;
    esac
    print_ok "MariaDB 官方源添加完成"
}

install_mariadb() {
    print_info "安装 MariaDB..."
    pkg_update

    case "$PKG_MGR" in
        apt)
            pkg_install mariadb-server mariadb-client
            ;;
        yum|dnf)
            pkg_install MariaDB-server MariaDB-client
            ;;
    esac

    if ! command -v mariadb &>/dev/null && ! command -v mysql &>/dev/null; then
        print_error "MariaDB 安装失败"
        exit 1
    fi

    local db_ver
    db_ver=$(mariadb --version 2>/dev/null || mysql --version 2>/dev/null)
    print_ok "MariaDB 安装完成: $db_ver"
}

configure_mariadb() {
    print_info "优化 MariaDB 配置 (小内存模式)..."

    local mem_mb mycnf_path
    mem_mb=$(get_mem_mb)

    local innodb_buffer_pool key_buffer query_cache tmp_table
    if [ "$mem_mb" -le 512 ]; then
        innodb_buffer_pool="64M"
        key_buffer="16M"
        query_cache="16M"
        tmp_table="16M"
    elif [ "$mem_mb" -le 1024 ]; then
        innodb_buffer_pool="128M"
        key_buffer="32M"
        query_cache="32M"
        tmp_table="32M"
    else
        innodb_buffer_pool="256M"
        key_buffer="64M"
        query_cache="64M"
        tmp_table="64M"
    fi

    # 查找配置目录
    if [ -d /etc/mysql/mariadb.conf.d ]; then
        mycnf_path="/etc/mysql/mariadb.conf.d/99-lnmp.cnf"
    elif [ -d /etc/my.cnf.d ]; then
        mycnf_path="/etc/my.cnf.d/lnmp.cnf"
    else
        mycnf_path="/etc/my.cnf"
    fi

    cat > "$mycnf_path" <<MYCNF
[mysqld]
user            = mysql
bind-address    = 127.0.0.1
port            = 3306

# 字符集
character-set-server  = utf8mb4
collation-server      = utf8mb4_unicode_ci

# InnoDB 配置 (小内存优化)
innodb_buffer_pool_size = ${innodb_buffer_pool}
innodb_log_file_size    = 32M
innodb_log_buffer_size  = 8M
innodb_flush_method     = O_DIRECT
innodb_file_per_table   = 1

# MyISAM
key_buffer_size = ${key_buffer}

# 查询缓存
query_cache_type = 1
query_cache_size = ${query_cache}

# 连接与临时表
max_connections     = 50
tmp_table_size      = ${tmp_table}
max_heap_table_size = ${tmp_table}

# 慢查询日志
slow_query_log      = 1
slow_query_log_file = /home/wwwlogs/mariadb_slow.log
long_query_time     = 2

# 安全
skip-name-resolve
local-infile = 0
symbolic-links = 0

[client]
default-character-set = utf8mb4
MYCNF

    print_ok "MariaDB 配置优化完成"
}

secure_mariadb() {
    print_info "初始化 MariaDB 安全设置..."

    # 启动服务
    systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null
    systemctl enable mariadb 2>/dev/null || systemctl enable mysql 2>/dev/null

    if [ -z "$DB_ROOT_PASS" ]; then
        DB_ROOT_PASS=$(gen_random_password)
    fi

    # 自动执行安全初始化
    local mysql_cmd
    mysql_cmd=$(command -v mariadb 2>/dev/null || command -v mysql 2>/dev/null)

    $mysql_cmd -u root <<SECURE_SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SECURE_SQL

    # 重启使配置生效
    systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null

    print_ok "MariaDB 安全初始化完成"
    print_info "MariaDB root 密码: ${BOLD}${DB_ROOT_PASS}${NC}"
}

setup_mariadb() {
    add_mariadb_repo
    install_mariadb
    configure_mariadb
    secure_mariadb
}
