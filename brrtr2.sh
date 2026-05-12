#!/bin/bash
# Файл: br-rtr_setup.sh
# Настройка маршрутизатора BR-RTR

set -e

sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

nmcli con mod eth0 ipv4.addresses 172.16.2.2/28 ipv4.method manual
nmcli con mod eth0 ipv4.gateway 172.16.2.1
nmcli con up eth0
nmcli con mod eth1 ipv4.addresses 192.168.4.1/28 ipv4.method manual
nmcli con up eth1

iptables -t nat -F
iptables -F FORWARD

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Проброс порта 8080 на testapp контейнер (порт 80 на BR-SRV)
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 8080 -j DNAT --to-destination 192.168.4.2:80
# Проброс порта 3226 на SSH порт 2026 BR-SRV
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 3226 -j DNAT --to-destination 192.168.4.2:2026

iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -d 192.168.4.2 --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp -d 192.168.4.2 --dport 2026 -j ACCEPT

iptables-save > /etc/sysconfig/iptables
systemctl enable iptables

# Маршрут до сетей за HQ-RTR (если нужно)
ip route add 192.168.1.0/27 via 172.16.2.1
ip route add 192.168.2.0/28 via 172.16.2.1
echo "192.168.1.0/27 via 172.16.2.1" >> /etc/sysconfig/network-scripts/route-eth0
echo "192.168.2.0/28 via 172.16.2.1" >> /etc/sysconfig/network-scripts/route-eth0