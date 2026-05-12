#!/bin/bash
# br-rtr_setup.sh

set -e

sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

dnf install -y nftables
systemctl enable nftables

mkdir -p /etc/nftables

cat > /etc/nftables/br.nft <<'EOF'
table inet nat {
    chain PREROUTING {
        type nat hook prerouting priority filter; policy accept;
        tcp dport 8080 dnat ip to 192.168.4.2:80
        tcp dport 3226 dnat ip to 192.168.4.2:2026
    }

    chain POSTROUTING {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ens160" masquerade
    }
}
EOF

nft -f /etc/nftables/br.nft
echo 'include "/etc/nftables/br.nft"' > /etc/nftables.conf
systemctl restart nftables

echo "BR-RTR настроен."