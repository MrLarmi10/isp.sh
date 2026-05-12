#!/bin/bash
# hq-rtr_setup.sh

set -e

# Включение IP-форвардинга
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Установка nftables
dnf install -y nftables
systemctl enable nftables
systemctl start nftables

# Создание таблиц и цепочек, если они отсутствуют (без flush)
nft add table inet nat 2>/dev/null || true
nft add chain inet nat prerouting { type nat hook prerouting priority -100 \; } 2>/dev/null || true
nft add chain inet nat postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true

nft add table inet filter 2>/dev/null || true
nft add chain inet filter forward { type filter hook forward priority 0 \; } 2>/dev/null || true

# Проброс порта 8080 на веб-приложение HQ-SRV (порт 80)
if ! nft list chain inet nat prerouting | grep -q "dport 8080 dnat to 192.168.1.2:80"; then
    nft add rule inet nat prerouting tcp dport 8080 dnat to 192.168.1.2:80
fi

# Проброс порта 3226 на SSH (порт 2026) HQ-SRV
if ! nft list chain inet nat prerouting | grep -q "dport 3226 dnat to 192.168.1.2:2026"; then
    nft add rule inet nat prerouting tcp dport 3226 dnat to 192.168.1.2:2026
fi

# Разрешение форварда для уже установленных соединений
if ! nft list chain inet filter forward | grep -q "ct state established,related accept"; then
    nft add rule inet filter forward ct state established,related accept
fi

# Разрешение форварда для портов 80 и 2026
if ! nft list chain inet filter forward | grep -q "tcp dport 80 accept"; then
    nft add rule inet filter forward tcp dport 80 accept
fi
if ! nft list chain inet filter forward | grep -q "tcp dport 2026 accept"; then
    nft add rule inet filter forward tcp dport 2026 accept
fi

# Сохранение полного ruleset (включая существующие правила)
nft list ruleset > /etc/nftables.conf
systemctl restart nftables