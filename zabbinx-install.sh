#!/bin/bash
#
# install_zabbix.sh
#
# 一鍵安裝 Zabbix 7.2 Server + Nginx 前端 + Agent
# 支援 Ubuntu 22.04 (jammy) 或 Ubuntu 24.04 (noble)
# 使用 MySQL (MariaDB) 作為資料庫，並以 Nginx + PHP-FPM 提供 Web 介面
#
# 使用方式：
#   sudo ./install-zabbix.sh
#

set -euo pipefail

############## 使用者可自行修改的變數 ##############

# Zabbix 資料庫使用者密碼 (請自行改成強密碼)
ZBX_DB_PASSWORD='YourZabbixDBPassword'

# PHP 時區 (可依需求自行修改)
PHP_TIMEZONE='Asia/Taipei'

############## 開始執行 ##############

echo "==========================================="
echo "  準備在此機器上安裝 Zabbix 7.2 (Nginx 前端)"
echo "==========================================="
echo

# ----- 1. 偵測 Ubuntu 版本 (22.04 jammy 或 24.04 noble) -----
OS_VERSION="$(. /etc/os-release && echo "$VERSION_ID")"
OS_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"


if [[ "$OS_VERSION" == "22.04" ]] && [[ "$OS_CODENAME" == "jammy" ]]; then
  ZBX_REPO_PKG="https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.2-1+ubuntu22.04_all.deb"
  PHP_FPM_SVC="php8.1-fpm"
elif [[ "$OS_VERSION" == "24.04" ]] && [[ "$OS_CODENAME" == "noble" ]]; then
  ZBX_REPO_PKG="https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.2-1+ubuntu24.04_all.deb"
  PHP_FPM_SVC="php8.3-fpm"
else
  echo "錯誤：目前作業系統版本為 $OS_VERSION ($OS_CODENAME)，本腳本僅支援 Ubuntu 22.04 (jammy) 或 24.04 (noble)。"
  exit 1
fi

echo "偵測到作業系統：Ubuntu $OS_VERSION ($OS_CODENAME)"
echo "將使用 Zabbix repository 套件："
echo "  $ZBX_REPO_PKG"
echo

# ----- 2. 更新 apt 套件列表並安裝必要工具 -----
echo "步驟 1/10：更新 apt 套件列表 & 安裝基礎工具..."
apt update
apt install -y wget curl gnupg lsb-release apt-transport-https

# ----- 3. 下載並安裝 Zabbix Repository 套件 -----
echo "步驟 2/10：下載並安裝 Zabbix Repository 套件..."
wget -O /tmp/zabbix-release.deb "${ZBX_REPO_PKG}"
dpkg -i /tmp/zabbix-release.deb
rm -f /tmp/zabbix-release.deb

# ----- 4. 重新更新 apt，以載入 Zabbix Repo -----
echo "步驟 3/10：更新 apt 套件列表 (含 Zabbix repo)..."
apt update

# ----- 5. 安裝 MySQL Server (實際是 MariaDB 相容版本) -----
echo "步驟 4/10：安裝 MySQL Server 並啟用服務..."
DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
systemctl enable --now mysql

# ----- 6. 建立 Zabbix 資料庫與使用者，並匯入初始 SQL -----
echo "步驟 5/10：建立 zabbix 資料庫、使用者，並匯入初始 SQL..."

# 等待 MySQL 啟動完成
echo "  等待 MySQL 啟動..."
until mysqladmin ping &>/dev/null; do
  sleep 2
done

# 開啟 log_bin_trust_function_creators，避免在建立函式時出錯
mysql -uroot <<EOF
SET GLOBAL log_bin_trust_function_creators = 1;
EOF

# 建立資料庫與使用者
mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZBX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

# 安裝 zabbix-sql-scripts 套件
apt install -y zabbix-sql-scripts

# 利用 dpkg -L 動態查路徑，尋找 SQL 檔案的完整路徑
SQL_PATH="$(dpkg -L zabbix-sql-scripts \
           | grep -m1 -E '/mysql/.*server\.sql(\.gz)?$' || true)"

if [[ -z "$SQL_PATH" ]]; then
  # 如果上面沒有找到，再試試 doc 目錄
  SQL_PATH="$(dpkg -L zabbix-sql-scripts \
             | grep -m1 -E '/doc/zabbix-sql-scripts/mysql/.*server\.sql(\.gz)?$' || true)"
fi

if [[ -z "$SQL_PATH" ]]; then
  echo "錯誤：找不到 Zabbix 初始資料庫結構檔（server.sql 或 server.sql.gz）。"
  exit 1
fi

echo "  找到 SQL 檔路徑：$SQL_PATH"
if [[ "$SQL_PATH" =~ \.gz$ ]]; then
  echo "  匯入 Zabbix 初始資料庫結構 (從 .gz 檔案)..."
  zcat "$SQL_PATH" | mysql -uzabbix -p"${ZBX_DB_PASSWORD}" zabbix
else
  echo "  匯入 Zabbix 初始資料庫結構 (從純 .sql 檔案)..."
  mysql -uzabbix -p"${ZBX_DB_PASSWORD}" zabbix < "$SQL_PATH"
fi

# 關閉 log_bin_trust_function_creators
mysql -uroot <<EOF
SET GLOBAL log_bin_trust_function_creators = 0;
EOF

# ----- 7. 安裝 Zabbix Server (MySQL)、Zabbix Agent、及前端所需 PHP 套件 -----
echo "步驟 6/10：安裝 Zabbix Server (MySQL)、Zabbix Agent、Zabbix 前端 (PHP)..."
apt install -y zabbix-server-mysql zabbix-agent zabbix-frontend-php

# ----- 8. 安裝 Nginx、PHP-FPM 及必要的 PHP 模組 -----
echo "步驟 7/10：安裝 Nginx、PHP-FPM 及必要 PHP 模組..."
apt install -y nginx php-fpm php-mysql php-xml php-bcmath php-mbstring php-gd

# ----- 9. 設定 Zabbix Server 配置檔，寫入資料庫密碼 -----
echo "步驟 8/10：設定 /etc/zabbix/zabbix_server.conf 的 DB 密碼..."
sed -i "s/^# DBPassword=/DBPassword=${ZBX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf

# ----- 10. 設定 PHP 時區 (修改 /etc/php/.../fpm/php.ini) -----
echo "步驟 9/10：設定 PHP 時區為 ${PHP_TIMEZONE}..."
PHP_INI_PATH="$(php -r 'echo php_ini_loaded_file();')"
if [[ -n "$PHP_INI_PATH" ]]; then
  sed -i "s@;date.timezone =@date.timezone = ${PHP_TIMEZONE}@" "$PHP_INI_PATH"
fi



# ---- 11. 自動調整 PHP 設定 ----
PHP_INI_FPM="/etc/php/8.3/fpm/php.ini"
sed -i "s/^post_max_size.*/post_max_size = 16M/" "$PHP_INI_FPM"
sed -i "s/^max_execution_time.*/max_execution_time = 300/" "$PHP_INI_FPM"
sed -i "s/^max_input_time.*/max_input_time = 300/" "$PHP_INI_FPM"

systemctl restart php8.3-fpm
systemctl restart nginx


echo "步驟 10/10：建立 Nginx 虛擬主機設定: /etc/nginx/sites-available/zabbix.conf"
cat > /etc/nginx/sites-available/zabbix.conf << 'EOF'
server {
    listen       80;
    #server_name  _;      # 可改為您的實際 IP 或網域

    root /usr/share/zabbix/ui;
    index index.php index.html index.htm;

    access_log  /var/log/nginx/zabbix_access.log;
    error_log   /var/log/nginx/zabbix_error.log;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass   unix:/run/php/php-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
        include        fastcgi_params;
    }

    # 靜態資源緩存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires max;
        log_not_found off;
    }
}
EOF

ln -sf /etc/nginx/sites-available/zabbix.conf /etc/nginx/sites-enabled/zabbix.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

# ----- 12. 啟動並設定開機自動啟動 -----
echo
echo "啟動並設定相關服務為開機自動啟動..."
for svc in zabbix-server zabbix-agent "${PHP_FPM_SVC}" nginx; do
  systemctl enable --now "$svc"
done

echo
echo "============================================="
echo "  Zabbix 7.2 安裝完成 (Ubuntu $OS_VERSION + Nginx)！"
echo
echo "  請用瀏覽器開啟： http://<伺服器IP或網域>/"
echo
echo "  預設登入帳號：Admin"
echo "  預設登入密碼：zabbix"
echo "============================================="

