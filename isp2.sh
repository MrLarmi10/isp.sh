#!/bin/bash
# isp_setup.sh - без настройки IP

set -e

dnf install -y chrony nginx httpd-tools

# Настройка NTP (chrony) как сервера stratum 5
cat > /etc/chrony.conf <<EOF
server ru.pool.ntp.org iburst
local stratum 5
allow 172.16.1.0/28
allow 172.16.2.0/28
allow 192.168.1.0/27
allow 192.168.2.0/28
allow 192.168.4.0/28
logdir /var/log/chrony
EOF
systemctl enable --now chronyd

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