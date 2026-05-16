#!/bin/bash
# isp_setup.sh - без настройки IP

set -e

dnf install -y chrony nginx httpd-tools

#!/bin/bash
# isp_ntp_setup.sh — настройка NTP сервера на ISP

set -e

echo "=== Установка chrony ==="
dnf install -y chrony

echo "=== Настройка /etc/chrony.conf ==="
cat > /etc/chrony.conf <<'EOF'
# Используем только один сервер с меткой prefer
server ntp1.vniiftri.ru iburst prefer
# Остальные серверы закомментированы
#server ntp2.unifitri.ru iburst
#server ntp3.unifitri.ru iburst
#server ntp4.unifitri.ru iburst

# Разрешаем доступ всем клиентам сети
allow 0.0.0.0/0

# Служим источником времени даже если не синхронизированы с внешним сервером
local stratum 5

# Путь для логов (опционально)
logdir /var/log/chrony
EOF

echo "=== Перезапуск chronyd ==="
systemctl restart chronyd
systemctl enable chronyd

echo "=== Проверка статуса (опционально) ==="
chronyc tracking


# Настройка nginx как обратного прокси с basic auth
mkdir -p /etc/nginx/conf.d
htpasswd -bc /etc/nginx/.htpasswd WEB P@sswOrd

cat > /etc/nginx/conf.d/web.au-team.irpo.conf <<EOF
server {
    listen 80;
    server_name web.au-team.irpo;
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
    location / {
        proxy_pass http://192.168.1.2:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

cat > /etc/nginx/conf.d/docker.au-team.irpo.conf <<EOF
server {
    listen 80;
    server_name docker.au-team.irpo;
    location / {
        proxy_pass http://192.168.4.2:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

systemctl enable --now nginx

# Включение маршрутизации (для проброса пакетов, если IP forwarding нужен)
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf