#!/bin/bash
# ==========================================================
# LNMP 一键安装脚本 - Nginx 安装模块
# 从官方仓库安装 Nginx，并优化小内存配置
# ==========================================================

add_nginx_repo() {
    print_info "添加 Nginx 官方源..."
    case "$OS_ID" in
        ubuntu)
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
                > /etc/apt/sources.list.d/nginx.list
            ;;
        debian)
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian $(lsb_release -cs) nginx" \
                > /etc/apt/sources.list.d/nginx.list
            ;;
        centos|rhel|rocky|almalinux)
            cat > /etc/yum.repos.d/nginx.repo <<'REPO'
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
REPO
            ;;
        fedora)
            cat > /etc/yum.repos.d/nginx.repo <<'REPO'
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/8/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
REPO
            ;;
    esac
    print_ok "Nginx 官方源添加完成"
}

install_nginx() {
    print_info "安装 Nginx..."
    pkg_update
    pkg_install nginx

    if ! command -v nginx &>/dev/null; then
        print_error "Nginx 安装失败"
        exit 1
    fi

    local nginx_ver
    nginx_ver=$(nginx -v 2>&1 | awk -F/ '{print $2}')
    print_ok "Nginx ${nginx_ver} 安装完成"
}

configure_nginx() {
    print_info "优化 Nginx 配置..."

    local mem_mb cpu_cores worker_connections
    mem_mb=$(get_mem_mb)
    cpu_cores=$(get_cpu_cores)

    if [ "$mem_mb" -le 512 ]; then
        worker_connections=512
    elif [ "$mem_mb" -le 1024 ]; then
        worker_connections=1024
    else
        worker_connections=2048
    fi

    local nginx_conf="/etc/nginx/nginx.conf"
    cp "$nginx_conf" "${nginx_conf}.bak" 2>/dev/null

    cat > "$nginx_conf" <<NGINX_CONF
user www;
worker_processes ${cpu_cores};
worker_rlimit_nofile 4096;
pid /var/run/nginx.pid;
error_log /home/wwwlogs/nginx_error.log warn;

events {
    use epoll;
    worker_connections ${worker_connections};
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /home/wwwlogs/nginx_access.log main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;

    keepalive_timeout 30;
    client_max_body_size 50m;
    client_body_buffer_size 256k;
    client_header_buffer_size 4k;
    large_client_header_buffers 4 32k;

    # Gzip 压缩
    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 16k;
    gzip_comp_level 4;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript
               image/svg+xml;
    gzip_vary on;
    gzip_disable "MSIE [1-6]\.";

    # 安全头
    server_tokens off;

    # FastCGI 缓存配置
    fastcgi_connect_timeout 300;
    fastcgi_send_timeout 300;
    fastcgi_read_timeout 300;
    fastcgi_buffer_size 64k;
    fastcgi_buffers 4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 256k;

    # 默认站点
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;
        root /home/wwwroot/default;
        index index.html index.htm index.php;

        location ~ \.php\$ {
            fastcgi_pass unix:/run/php-fpm/www.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }

        location ~ /.well-known {
            allow all;
        }

        location ~ /\. {
            deny all;
        }
    }

    # 加载虚拟主机配置
    include /usr/local/nginx/conf/vhost/*.conf;
}
NGINX_CONF

    # 默认首页
    cat > /home/wwwroot/default/index.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>LNMP 安装成功</title>
    <style>
        body { font-family: -apple-system, sans-serif; display: flex;
               justify-content: center; align-items: center; min-height: 100vh;
               margin: 0; background: #f5f5f5; }
        .card { background: white; padding: 40px 60px; border-radius: 12px;
                box-shadow: 0 2px 12px rgba(0,0,0,0.1); text-align: center; }
        h1 { color: #333; margin-bottom: 8px; }
        p { color: #666; }
        .ok { color: #22c55e; font-size: 48px; }
    </style>
</head>
<body>
    <div class="card">
        <div class="ok">&#10003;</div>
        <h1>LNMP 环境安装成功</h1>
        <p>Nginx + MariaDB + PHP 已就绪</p>
    </div>
</body>
</html>
HTML

    chown -R www:www /home/wwwroot/default
    print_ok "Nginx 配置优化完成"
}

setup_nginx() {
    add_nginx_repo
    install_nginx
    configure_nginx
}
