#!/bin/bash

# Colors
RESET="\033[0m"
BLUE="\033[1;34m"
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"

# Helper Functions
log_GREEN() {
    echo -e "${GREEN}$1${RESET}"
}

log_RED() {
    echo -e "${RED}$1${RESET}"
}

log_BLUE() {
    echo -e "${BLUE}$1${RESET}"
}

log_YELLOW() {
    echo -e "${YELLOW}$1${RESET}"
}

log_CYAN() {
    echo -e "${CYAN}$1${RESET}"
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  log_RED "请以root权限运行此脚本。"
  exit 1
fi

# 检查并安装必要的软件包
install_if_missing() {
  PACKAGE_NAME=$1
  if ! dpkg -l | grep -q "^ii  $PACKAGE_NAME "; then
    log_YELLOW "$PACKAGE_NAME 未安装，正在安装..."
    sudo apt install -y $PACKAGE_NAME
  else
    log_GREEN "$PACKAGE_NAME 已安装。"
  fi
}

# 检查自动续订任务是否存在
setup_cron_job() {
  CRON_JOB="0 0 1 * * /usr/bin/certbot renew --deploy-hook 'nginx -s reload'"
  if crontab -l 2>/dev/null | grep -q "$CRON_JOB"; then
    log_GREEN "证书自动续订任务已存在。"
  else
    log_YELLOW "配置证书自动续订任务..."
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    log_GREEN "证书自动续订任务已添加。"
  fi
}

REMOTE_SCRIPT_URL="https://raw.githubusercontent.com/lthero-big/QcHTTPS/refs/heads/main/install_https.sh"
# 脚本信息
SCRIPT_VERSION="V_1.0.0"
# 更新脚本功能
update_script() {
  echo -e "${GREEN}正在检查脚本更新...${RESET}"
  # 设置超时时间为 10 秒
  REMOTE_VERSION=$(curl --max-time 10 -fsSL "$REMOTE_SCRIPT_URL" | grep -E "^SCRIPT_VERSION=" | cut -d'"' -f2)
  # 检查是否成功获取远程版本
  if [ $? -ne 0 ]; then
    log_YELLOW "无法获取到最新版本 (超时或网络问题)."
    return
  fi

  if [ "$REMOTE_VERSION" != "$SCRIPT_VERSION" ]; then
    log_GREEN "发现新版本 ($REMOTE_VERSION) ，当前版本 $SCRIPT_VERSION."
    log_GREEN "是否更新脚本? (y/N)"
    read update_choice
    if [[ "$update_choice" == "y" || "$update_choice" == "Y" ]]; then
      log_GREEN "Updating script..."
      curl --max-time 10 -fsSL "$REMOTE_SCRIPT_URL" -o "$0"
      if [ $? -eq 0 ]; then
        chmod +x "$0"
        log_GREEN "脚本已经更新为 $REMOTE_VERSION. 请重新运行脚本."
        exit 0
      else
        log_RED "脚本更新失败."
      fi
    fi
  else
    log_GREEN "当前脚本已为最新版本: $SCRIPT_VERSION."
  fi
}

update_script

# 菜单功能
log_BLUE "请选择操作:"
log_CYAN "1. 配置 HTTPS"
log_CYAN "2. 查看当前启用的 Nginx 配置"
log_CYAN "3. 更新脚本"
log_CYAN "q. 退出脚本"
read -p "请输入选项 (1/2/3/q): " CHOICE

case $CHOICE in
  1)
    # 获取用户输入
    read -p "请输入域名 (例如: xx.lthero.cn): " DOMAIN
    read -p "请输入本地服务器端口号 (例如: 3001): " PORT
    read -p "请输入用于申请证书的邮箱地址: " EMAIL

    # 更新系统包
    log_BLUE "更新系统包..."
    sudo apt update

    # 安装必要的软件包
    log_BLUE "检查并安装必要的软件包..."
    install_if_missing "nginx"
    install_if_missing "certbot"
    install_if_missing "python3-certbot-nginx"

    # 配置Nginx
    NGINX_CONFIG="/etc/nginx/sites-available/$DOMAIN"
    NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"

    cat <<EOF > $NGINX_CONFIG
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    # 启用配置
    ln -s $NGINX_CONFIG $NGINX_ENABLED

    # 检查Nginx配置并重新加载
    nginx -t
    if [ $? -ne 0 ]; then
      log_RED "Nginx配置有误，请检查！"
      exit 1
    fi
    sudo systemctl reload nginx

    # 申请并配置SSL证书
    certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect
    if [ $? -ne 0 ]; then
      log_RED "证书申请失败，请检查域名和DNS设置。"
      exit 1
    fi
    log_GREEN "证书申请成功，证书位置于 /etc/letsencrypt/live/"

    # 配置自动续订
    setup_cron_job

    # 完成
    log_GREEN "HTTPS配置完成！现在可以通过 https://$DOMAIN 访问您的服务。"
    ;;
  2)
    # 查看当前启用的 Nginx 配置
    log_CYAN "当前启用的 Nginx 配置文件:"
    ls -l /etc/nginx/sites-enabled/
    log_CYAN "对应的配置文件路径:"
    for file in /etc/nginx/sites-enabled/*; do
      realpath "$file"
    done
    ;;
  3)
    # 更新脚本
    update_script
    ;;
  q)
    # 退出脚本
    log_GREEN "退出脚本。"
    exit 0
    ;;
  *)
    log_RED "无效选项，请重新运行脚本并选择 1, 2, 3 或 q。"
    exit 1
    ;;
esac

# Nginx 上传文件大小限制
# 默认情况下，Nginx 会对上传文件的大小有限制，通常为 1 MB。
# 如果需要更大限制，可以在 Nginx 配置中添加以下内容：
# client_max_body_size 100m;  # 将大小限制调整为 100MB
