#!/bin/bash
# hq-rtr_setup.sh

set -e

# Включение IP-форвардинга
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Установка nftables
dnf install -y nftables
systemctl enable nftables

# Создание каталога для конфигов
mkdir -p /etc/nftables

# Запись файла hq.nft
cat > /etc/nftables/hq.nft <<'EOF'
table inet nat {
    chain PREROUTING {
        type nat hook prerouting priority filter; policy accept;
        tcp dport 8080 dnat ip to 192.168.1.2:80
        tcp dport 3226 dnat ip to 192.168.1.2:2026
    }

    chain POSTROUTING {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ens160" masquerade
    }
}
EOF

# Загрузка правил
nft -f /etc/nftables/hq.nft

# Сохранение правил (чтобы загружались при старте)
echo 'include "/etc/nftables/hq.nft"' > /etc/nftables.conf
systemctl restart nftables

echo "HQ-RTR настроен."