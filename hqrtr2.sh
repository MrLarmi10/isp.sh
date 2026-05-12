#!/bin/bash
# hq-rtr_setup.sh - без настройки IP

set -e

# Включение форвардинга
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Очистка предыдущих правил NAT
iptables -t nat -F
iptables -F FORWARD

# Маскарадинг для выхода в интернет (правило без привязки к интерфейсу)
iptables -t nat -A POSTROUTING -s 192.168.1.0/27 -o + -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.2.0/28 -o + -j MASQUERADE

# Проброс порта 8080 на веб-приложение HQ-SRV (порт 80)
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.2:80
# Проброс порта 3226 на SSH (порт 2026) HQ-SRV
iptables -t nat -A PREROUTING -p tcp --dport 3226 -j DNAT --to-destination 192.168.1.2:2026

# Разрешить форвард для принятых соединений
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -d 192.168.1.2 --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp -d 192.168.1.2 --dport 2026 -j ACCEPT

# Сохранение правил
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables