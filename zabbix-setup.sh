# Ubuntu 24.04 安裝 Zabbix 7.2 (Nginx + MariaDB + PHP-FPM) SOP

---

## 1. 更新套件庫與安裝必要工具

```
apt update
apt install -y wget curl gnupg lsb-release apt-transport-https
```

---

## 2. 安裝 Zabbix Repository

```
wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/7.2/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.2-1+ubuntu24.04_all.deb
dpkg -i /tmp/zabbix-release.deb
rm -f /tmp/zabbix-release.deb
apt update
```

---

## 3. 安裝 MariaDB (MySQL 相容)

```
DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
systemctl enable --now mysql
```

---

## 4. 建立 Zabbix 資料庫與帳號

（請將 `YourZabbixDBPassword` 換成你自訂的安全密碼）

```
mysql -uroot <<EOF
SET GLOBAL log_bin_trust_function_creators = 1;
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'YourZabbixDBPassword';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF
```

---

## 5. 安裝 zabbix-sql-scripts

```
apt install -y zabbix-sql-scripts
```

---

## 6. 匯入 Zabbix 資料表結構

> 自動尋找 SQL 路徑（可用指令方式完成）

```
SQL_PATH="$(dpkg -L zabbix-sql-scripts | grep -m1 -E '/mysql/.*server\.sql(\.gz)?$')"
zcat "$SQL_PATH" | mysql -uzabbix -p'YourZabbixDBPassword' zabbix
```

> 輸入 zabbix 密碼（YourZabbixDBPassword）

```
mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"
```

---

## 7. 安裝 Zabbix 伺服器、Agent、前端

```
apt install -y zabbix-server-mysql zabbix-agent zabbix-frontend-php
```

---

## 8. 安裝 Nginx、PHP-FPM 及 PHP 套件

```
apt install -y nginx php-fpm php-mysql php-xml php-bcmath php-mbstring php-gd
```

---

## 9. 設定 Zabbix 連線資料庫密碼

```
sed -i "s/^# DBPassword=/DBPassword=YourZabbixDBPassword/" /etc/zabbix/zabbix_server.conf
```

---

## 10. 設定 PHP 時區（以 Asia/Taipei 為例）

```
sed -i "s@;date.timezone =@date.timezone = Asia/Taipei@" /etc/php/8.3/fpm/php.ini
```

---

## 11. 調整 PHP 部分參數（可視需求調整）

```
sed -i "s/^post_max_size.*/post_max_size = 16M/" /etc/php/8.3/fpm/php.ini
sed -i "s/^max_execution_time.*/max_execution_time = 300/" /etc/php/8.3/fpm/php.ini
sed -i "s/^max_input_time.*/max_input_time = 300/" /etc/php/8.3/fpm/php.ini
```

---

## 12. 重啟 PHP-FPM 與 Nginx

```
systemctl restart php8.3-fpm
systemctl restart nginx
```

---

## 13. 建立 Nginx Zabbix 站台設定檔

```
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
```

---

## 14. 啟用並自動啟動服務

```
systemctl enable --now zabbix-server zabbix-agent php8.3-fpm nginx
```

---

## 15. 開啟瀏覽器設定 Zabbix

```
http://<你的伺服器IP或網域>/
```

---

### 預設帳號密碼

* 預設登入帳號：admin
* 預設密碼：zabbix
