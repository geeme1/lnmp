# LNMP 一键安装脚本

轻量、干净、透明的 LNMP (Linux + Nginx + MariaDB + PHP) 一键安装脚本，专为小内存 VPS 优化。

## 特性

- **多系统支持**: Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux
- **PHP 版本可选**: 7.2 / 7.3 / 7.4 / 8.0 / 8.1 / 8.2
- **MariaDB 10.11 LTS**: 比 MySQL 更轻量，完全兼容
- **SSL 证书**: acme.sh + Let's Encrypt 自动申请/续期
- **小内存优化**: 512MB VPS 即可流畅运行
- **安全透明**: 无后门、无数据外传，代码完全开源可审计

## 一键安装

```bash
wget https://github.com/geeme1/lnmp/archive/refs/heads/main.tar.gz -O lnmp.tar.gz && tar zxf lnmp.tar.gz && cd lnmp-main && chmod +x install.sh && ./install.sh
```

## 管理命令

```bash
lnmp start              # 启动所有服务
lnmp stop               # 停止所有服务
lnmp restart            # 重启所有服务
lnmp reload             # 平滑重载配置
lnmp status             # 查看服务状态

lnmp vhost add          # 添加虚拟主机
lnmp vhost del          # 删除虚拟主机
lnmp vhost list         # 列出虚拟主机

lnmp ssl add example.com  # 申请 SSL 证书
lnmp ssl renew             # 续期所有证书

lnmp info               # 查看安装信息
```

## 目录结构

| 路径 | 说明 |
|------|------|
| `/home/wwwroot/` | 站点文件目录 |
| `/home/wwwlogs/` | 日志目录 |
| `/etc/nginx/nginx.conf` | Nginx 主配置 |
| `/usr/local/nginx/conf/vhost/` | 虚拟主机配置 |
| `/usr/local/nginx/conf/ssl/` | SSL 证书 |

## 512MB 内存优化策略

- 自动创建 1GB Swap 交换分区
- PHP-FPM 使用 ondemand 模式，空闲不占内存
- MariaDB InnoDB 缓冲池限制为 64MB
- Nginx worker_connections 限制为 512

## 许可证

MIT
