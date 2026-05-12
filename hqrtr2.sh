#!/bin/bash
# Файл: hq-rtr_setup.sh
# Настройка маршрутизатора HQ-RTR

set -e

# Включение форвардинга
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Настройка интерфейсов
nmcli con mod eth0 ipv4.addresses 172.16.1.2/28 ipv4.method manual
nmcli con mod eth0 ipv4.gateway 172.16.1.1
nmcli con up eth0
nmcli con mod eth1 ipv4.addresses 192.168.1.1/27 ipv4.method manual
nmcli con up eth1
nmcli con mod eth2 ipv4.addresses 192.168.2.1/28 ipv4.method manual
nmcli con up eth2

# Очистка предыдущих правил NAT (если есть)
iptables -t nat -F
iptables -F FORWARD

# Маскарадинг для выхода в интернет через ISP
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Проброс порта 8080 (внешний) на веб-приложение HQ-SRV (порт 80)
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.2:80
# Проброс порта 3226 на SSH (порт 2026) HQ-SRV
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 3226 -j DNAT --to-destination 192.168.1.2:2026

# Разрешить форвард для принятых соединений
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -d 192.168.1.2 --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp -d 192.168.1.2 --dport 2026 -j ACCEPT

# Сохранение правил (для RedOS iptables-save)
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables

# Маршрут до сети BR-RTR (обратный)
ip route add 192.168.4.0/28 via 172.16.1.1
echo "192.168.4.0/28 via 172.16.1.1" >> /etc/sysconfig/network-scripts/route-eth0