#!/bin/bash
# br-rtr_setup.sh — исправленная версия с dnat ip

set -e

sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

dnf install -y nftables
systemctl enable nftables
systemctl start nftables

nft add table inet nat 2>/dev/null || true
nft add chain inet nat prerouting { type nat hook prerouting priority -100 \; } 2>/dev/null || true
nft add chain inet nat postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true

nft add table inet filter 2>/dev/null || true
nft add chain inet filter forward { type filter hook forward priority 0 \; } 2>/dev/null || true

# Проброс порта 8080 на testapp (BR-SRV)
if ! nft list chain inet nat prerouting | grep -q "dport 8080 dnat ip to 192.168.4.2:80"; then
    nft add rule inet nat prerouting tcp dport 8080 dnat ip to 192.168.4.2:80
fi

# Проброс порта 3226 на SSH (BR-SRV, порт 2026)
if ! nft list chain inet nat prerouting | grep -q "dport 3226 dnat ip to 192.168.4.2:2026"; then
    nft add rule inet nat prerouting tcp dport 3226 dnat ip to 192.168.4.2:2026
fi

# Разрешение форварда
if ! nft list chain inet filter forward | grep -q "ct state established,related accept"; then
    nft add rule inet filter forward ct state established,related accept
fi

if ! nft list chain inet filter forward | grep -q "tcp dport 80 accept"; then
    nft add rule inet filter forward tcp dport 80 accept
fi
if ! nft list chain inet filter forward | grep -q "tcp dport 2026 accept"; then
    nft add rule inet filter forward tcp dport 2026 accept
fi

nft list ruleset > /etc/nftables.conf
systemctl restart nftables