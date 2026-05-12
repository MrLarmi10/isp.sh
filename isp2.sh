#!/bin/bash
# Файл: isp_setup.sh
# Полная настройка маршрутизатора ISP

set -e

dnf install -y chrony nginx httpd-tools

# Настройка интерфейсов (пример с nmcli, имена ens192 и ens254)
nmcli con mod ens192 ipv4.addresses 172.16.1.1/28 ipv4.method manual
nmcli con mod ens192 ipv4.gateway "" 
nmcli con up ens192
nmcli con mod ens254 ipv4.addresses 172.16.2.1/28 ipv4.method manual
nmcli con up ens254

# Статические маршруты до сетей за HQ-RTR и BR-RTR
ip route add 192.168.1.0/27 via 172.16.1.2
ip route add 192.168.2.0/28 via 172.16.1.2
ip route add 192.168.4.0/28 via 172.16.2.2
echo "192.168.1.0/27 via 172.16.1.2" >> /etc/sysconfig/network-scripts/route-ens192
echo "192.168.2.0/28 via 172.16.1.2" >> /etc/sysconfig/network-scripts/route-ens192
echo "192.168.4.0/28 via 172.16.2.2" >> /etc/sysconfig/network-scripts/route-ens254

# Настройка NTP (chrony) как сервера с stratum 5
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

# Включение маршрутизации (на всякий случай)
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf