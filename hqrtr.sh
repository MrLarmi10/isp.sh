#!/bin/bash

hostnamectl set-hostname hq-rtr.au-team.irpo
timedatectl set-timezone Europe/Moscow

# Интерфейсы
# К ISP
nmcli con mod ens192 ipv4.addresses 172.168.1.2/27 ipv4.gateway 172.168.1.1 ipv4.method manual
nmcli con up ens192

# Туннель GRE к BR-RTR
nmcli con add type ip-tunnel ifname tun1 con-name tun1 mode gre remote 172.168.2.2 local 172.168.1.2
nmcli con mod tun1 ipv4.addresses 10.0.0.1/30 ipv4.method manual
nmcli con mod tun1 ip-tunnel.ttl 64
nmcli con up tun1

# VLAN-ы (один физический порт ens224)
# VLAN 10 - HQ-SRV
nmcli con add type vlan dev ens224 id 10 con-name vlan10
nmcli con mod vlan10 ipv4.addresses 192.168.10.1/26 ipv4.method manual
# VLAN 20 - HQ-CLI
nmcli con add type vlan dev ens224 id 20 con-name vlan20
nmcli con mod vlan20 ipv4.addresses 192.168.20.1/27 ipv4.method manual
# VLAN 99 - управление
nmcli con add type vlan dev ens224 id 99 con-name vlan99
nmcli con mod vlan99 ipv4.addresses 192.168.99.1/28 ipv4.method manual

# Включение форвардинга
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# NAT в сторону ISP
dnf install -y nftables
cat > /etc/nftables/hq-nat.nft <<EOF
table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "ens192" masquerade
  }
}
EOF
echo 'include "/etc/nftables/hq-nat.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables

# FRR (OSPF)
dnf install -y frr
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr

vtysh <<EOF
configure terminal
router ospf
 passive-interface default
 network 10.0.0.0/30 area 0
 network 192.168.10.0/26 area 0
 network 192.168.20.0/27 area 0
 network 192.168.99.0/28 area 0
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

# Статический NAT (проброс портов)
# 8080 -> HQ-SRV:80, 2026 -> HQ-SRV:2026
nft add rule ip nat prerouting tcp dport 8080 dnat to 192.168.10.2:80
nft add rule ip nat prerouting tcp dport 2026 dnat to 192.168.10.2:2026

# DHCP для VLAN 20
dnf install -y dhcp-server
cat > /etc/dhcp/dhcpd.conf <<EOF
subnet 172.168.1.0 netmask 255.255.255.224 {
  range 172.168.1.1 172.168.1.20;
  option domain-name-servers 172.168.1.2;
  option domain-name "au-team.irpo";
  option routers 172.168.1.1;
  default-lease-time 600;
  max-lease-time 7200;
}
EOF
systemctl enable --now dhcpd

echo "HQ-RTR настройка завершена"