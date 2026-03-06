#!/bin/bash
# ==========================================================
# LNMP 一键安装脚本 - 公共函数模块
# 包含：颜色输出、系统检测、基础工具函数
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info()  { echo -e "${CYAN}[信息]${NC} $1"; }
print_ok()    { echo -e "${GREEN}[完成]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║        LNMP 一键安装脚本 v1.0                   ║"
    echo "║        Nginx + MariaDB + PHP                    ║"
    echo "║        适配小内存 VPS (512MB+)                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 用户运行此脚本 (sudo ./install.sh)"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION_ID="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
        OS_MAJOR_VERSION="${VERSION_ID%%.*}"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
        OS_VERSION_ID=$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null || echo "7")
        OS_NAME=$(cat /etc/redhat-release)
        OS_MAJOR_VERSION="${OS_VERSION_ID%%.*}"
    else
        print_error "无法识别操作系统"
        exit 1
    fi

    case "$OS_ID" in
        ubuntu|debian)
            PKG_MGR="apt"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf &>/dev/null; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        *)
            print_error "不支持的操作系统: $OS_ID ($OS_NAME)"
            print_error "支持: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux"
            exit 1
            ;;
    esac

    print_info "检测到系统: ${BOLD}$OS_NAME${NC}"
}

pkg_update() {
    print_info "更新软件源..."
    case "$PKG_MGR" in
        apt) apt-get update -y -qq ;;
        yum) yum makecache -q ;;
        dnf) dnf makecache -q ;;
    esac
}

pkg_install() {
    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
        yum) yum install -y -q "$@" ;;
        dnf) dnf install -y -q "$@" ;;
    esac
}

get_mem_mb() {
    awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo
}

get_cpu_cores() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1
}

get_ip() {
    curl -s --connect-timeout 5 ifconfig.me 2>/dev/null \
        || curl -s --connect-timeout 5 ip.sb 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}' \
        || echo "未知"
}

setup_swap() {
    local mem_mb
    mem_mb=$(get_mem_mb)

    if [ "$mem_mb" -lt 1024 ] && [ ! -f /swapfile ]; then
        print_info "内存 ${mem_mb}MB，创建 1GB 交换分区..."
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile

        if ! grep -q '/swapfile' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi

        sysctl vm.swappiness=10
        if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
            echo 'vm.swappiness=10' >> /etc/sysctl.conf
        fi

        print_ok "交换分区创建完成 (1GB)"
    elif [ -f /swapfile ]; then
        print_info "交换分区已存在，跳过"
    else
        print_info "内存 ${mem_mb}MB，无需创建交换分区"
    fi
}

install_base_deps() {
    print_info "安装基础依赖..."
    case "$PKG_MGR" in
        apt)
            pkg_install curl wget gnupg2 ca-certificates lsb-release \
                apt-transport-https software-properties-common \
                cron tar gzip unzip
            ;;
        yum|dnf)
            pkg_install curl wget ca-certificates epel-release \
                cronie tar gzip unzip
            ;;
    esac
    print_ok "基础依赖安装完成"
}

create_www_user() {
    if ! id www &>/dev/null; then
        groupadd -f www
        useradd -r -g www -s /sbin/nologin -M www
        print_ok "创建用户 www"
    fi
}

create_dirs() {
    mkdir -p /home/wwwroot/default
    mkdir -p /home/wwwlogs
    mkdir -p /usr/local/nginx/conf/vhost
    chown -R www:www /home/wwwroot
    chown -R www:www /home/wwwlogs
}

gen_random_password() {
    tr -dc 'A-Za-z0-9!@#$%&*' < /dev/urandom | head -c 16
}

confirm_continue() {
    local msg="${1:-是否继续？}"
    echo -en "${YELLOW}${msg} [Y/n]: ${NC}"
    read -r ans
    case "$ans" in
        [nN]|[nN][oO]) return 1 ;;
        *) return 0 ;;
    esac
}

print_separator() {
    echo -e "${BLUE}──────────────────────────────────────────${NC}"
}
