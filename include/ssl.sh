#!/bin/bash
# ==========================================================
# LNMP 一键安装脚本 - SSL 证书模块
# 使用 acme.sh 申请 Let's Encrypt 免费 SSL 证书
# acme.sh 比 certbot 更轻量，适合小内存 VPS
# ==========================================================

install_acme() {
    print_info "安装 acme.sh SSL 证书管理工具..."

    if [ -f ~/.acme.sh/acme.sh ]; then
        print_info "acme.sh 已安装，更新中..."
        ~/.acme.sh/acme.sh --upgrade
    else
        curl -fsSL https://get.acme.sh | sh -s email="${ACME_EMAIL:-admin@example.com}"
    fi

    if [ ! -f ~/.acme.sh/acme.sh ]; then
        print_error "acme.sh 安装失败"
        return 1
    fi

    # 设置默认 CA 为 Let's Encrypt
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    mkdir -p /usr/local/nginx/conf/ssl

    print_ok "acme.sh 安装完成"
}

issue_ssl_cert() {
    local domain="$1"

    if [ -z "$domain" ]; then
        print_error "请指定域名"
        return 1
    fi

    print_info "为 ${domain} 申请 SSL 证书..."

    local webroot="/home/wwwroot/${domain}"
    mkdir -p "${webroot}/.well-known/acme-challenge"
    chown -R www:www "$webroot"

    # 使用 webroot 方式验证
    ~/.acme.sh/acme.sh --issue \
        -d "$domain" \
        --webroot "$webroot" \
        --keylength 2048 \
        --force

    if [ $? -ne 0 ]; then
        print_warn "webroot 验证失败，尝试 standalone 方式..."
        systemctl stop nginx
        ~/.acme.sh/acme.sh --issue \
            -d "$domain" \
            --standalone \
            --keylength 2048 \
            --force
        systemctl start nginx
    fi

    local ssl_dir="/usr/local/nginx/conf/ssl/${domain}"
    mkdir -p "$ssl_dir"

    # 安装证书
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "${ssl_dir}/privkey.pem" \
        --fullchain-file "${ssl_dir}/fullchain.pem" \
        --reloadcmd "systemctl reload nginx"

    if [ $? -eq 0 ]; then
        print_ok "SSL 证书申请并安装成功: ${domain}"
        print_info "证书路径: ${ssl_dir}/"
        print_info "证书将自动续期"
        return 0
    else
        print_error "SSL 证书申请失败，请检查域名解析是否正确"
        return 1
    fi
}

generate_ssl_vhost() {
    local domain="$1"
    local webroot="/home/wwwroot/${domain}"
    local ssl_dir="/usr/local/nginx/conf/ssl/${domain}"
    local vhost_file="/usr/local/nginx/conf/vhost/${domain}.conf"
    local php_sock
    php_sock=$(cat /usr/local/nginx/conf/.php_fpm_sock 2>/dev/null || echo "/run/php-fpm/www.sock")

    cat > "$vhost_file" <<VHOST
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};
    root ${webroot};
    index index.html index.htm index.php;

    ssl_certificate     ${ssl_dir}/fullchain.pem;
    ssl_certificate_key ${ssl_dir}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # PHP 支持
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
    }

    access_log /home/wwwlogs/${domain}_access.log main;
    error_log  /home/wwwlogs/${domain}_error.log warn;
}
VHOST

    systemctl reload nginx
    print_ok "SSL 虚拟主机配置已更新: ${domain}"
}

setup_ssl() {
    echo ""
    print_separator
    echo -en "${BOLD}请输入用于 SSL 证书注册的邮箱 (默认 admin@example.com): ${NC}"
    read -r email_input
    ACME_EMAIL="${email_input:-admin@example.com}"

    install_acme
}
