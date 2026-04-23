#!/bin/bash

hostnamectl set-hostname br-rtr.au-team.irpo
timedatectl set-timezone Europe/Moscow

# К ISP
nmcli con mod ens192 ipv4.addresses 172.168.2.2/27 ipv4.gateway 172.168.2.1 ipv4.method manual
nmcli con up ens192

# Туннель GRE к HQ-RTR
nmcli con add type ip-tunnel ifname tun1 con-name tun1 mode gre remote 172.168.1.2 local 172.168.2.2
nmcli con mod tun1 ipv4.addresses 10.0.0.2/30 ipv4.method manual
nmcli con mod tun1 ip-tunnel.ttl 64
nmcli con up tun1

# Локальная сеть BR-SRV (маска /28)
nmcli con mod ens224 ipv4.addresses 192.168.200.1/28 ipv4.method manual
nmcli con up ens224

# Форвардинг
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# NAT
dnf install -y nftables
cat > /etc/nftables/br-nat.nft <<EOF
table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "ens192" masquerade
  }
}
EOF
echo 'include "/etc/nftables/br-nat.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables

# FRR OSPF
dnf install -y frr
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr

vtysh <<EOF
configure terminal
router ospf
 passive-interface default
 network 10.0.0.0/30 area 0
 network 192.168.200.0/28 area 0
 area 0 authentication
 exit
 interface tun1
  no ip ospf passive
  ip ospf authentication
  ip ospf authentication-key P@sswOrd
 exit
 exit
 write
EOF
systemctl restart frr

# Проброс портов: 8080 -> BR-SRV, 2026 -> BR-SRV
nft add rule ip nat prerouting tcp dport 8080 dnat to 192.168.200.2:8080
nft add rule ip nat prerouting tcp dport 2026 dnat to 192.168.200.2:2026

# Пользователь net_admin
useradd net_admin
echo "P@sswOrd" | passwd --stdin net_admin
echo "net_admin ALL=(ALL) ALL" >> /etc/sudoers

echo "BR-RTR настройка завершена"