#!/bin/bash

# ===== ISP ROUTER =====
hostnamectl set-hostname isp.au-team.irpo

# Включение маршрутизации
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# DHCP на внешнем интерфейсе
nmcli con mod ens160 ipv4.method auto
nmcli con up ens160

# Интерфейс к HQ
nmcli con mod ens192 ipv4.addresses 172.168.1.1/27 ipv4.method manual
nmcli con up ens192

# Интерфейс к BR
nmcli con mod ens224 ipv4.addresses 172.168.2.1/27 ipv4.method manual
nmcli con up ens224

# NAT
cat > /etc/nftables/isp.nft 
table inet nat {
 chain POSTROUTING {
  type nat hook postrouting priority srcnat;
  oifname "ens160" masquerade
 }
}


echo 'include "/etc/nftables/isp.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables

# Timezone
timedatectl set-timezone Europe/Moscow

echo "ISP configured"