#!/bin/bash

# =====================================================
# МОДУЛЬ 2: Настройка ISP-RTR
# - Nginx как обратный прокси
# - web.au-team.irpo -> HQ-SRV:80 (через проброс 8080)
# - docker.au-team.irpo -> BR-SRV:8080
# - Basic аутентификация для web.au-team.irpo
# =====================================================

set -e

echo "=== МОДУЛЬ 2: Настройка ISP-RTR ==="

# 1. Установка Nginx
dnf install -y nginx httpd-tools

# 2. Создание файла паролей (.htpasswd)
htpasswd -b -c /etc/nginx/.htpasswd WEBc P@sswOrd

# 3. Настройка Nginx
cat > /etc/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 4096;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Прокси для web.au-team.irpo (с аутентификацией)
    server {
        listen 80;
        server_name web.au-team.irpo;

        auth_basic "Authorized access only";
        auth_basic_user_file /etc/nginx/.htpasswd;

        location / {
            proxy_pass http://172.168.1.2:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }

    # Прокси для docker.au-team.irpo (без аутентификации)
    server {
        listen 80;
        server_name docker.au-team.irpo;

        location / {
            proxy_pass http://172.168.2.2:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
EOF

# 4. Запуск Nginx
systemctl enable --now nginx

echo "=== МОДУЛЬ 2: ISP-RTR готова ==="