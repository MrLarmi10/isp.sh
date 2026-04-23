#!/bin/bash

# usage:
# bash routers.sh hq
# bash routers.sh br

TYPE=$1

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

if [ "$TYPE" == "hq" ]; then
    hostnamectl set-hostname hq-rtr.au-team.irpo

    nmcli con mod ens160 ipv4.addresses 172.168.1.2/27 ipv4.gateway 172.168.1.1 ipv4.method manual
    nmcli con up ens160

    # VLAN 10
    nmcli con add type vlan con-name ens192.10 dev ens192 id 10 ip4 192.168.10.1/26

    # VLAN 20
    nmcli con add type vlan con-name ens192.20 dev ens192 id 20 ip4 192.168.20.1/27

    # VLAN 99
    nmcli con add type vlan con-name ens192.99 dev ens192 id 99 ip4 192.168.99.1/28

    # DHCP
    dnf install dhcp-server -y
    cat > /etc/dhcp/dhcpd.conf <<EOF
subnet 192.168.20.0 netmask 255.255.255.224 {
 range 192.168.20.2 192.168.20.30;
 option routers 192.168.20.1;
 option domain-name-servers 192.168.10.2;
 option domain-name "au-team.irpo";
}
EOF
    systemctl enable --now dhcpd

    # GRE
    nmcli con add type ip-tunnel ip-tunnel.mode gre con-name tun1 ifname tun1 remote 172.168.2.2 local 172.168.1.2
    nmcli con mod tun1 ipv4.addresses 10.10.10.1/30
    nmcli con up tun1

elif [ "$TYPE" == "br" ]; then
    hostnamectl set-hostname br-rtr.au-team.irpo

    nmcli con mod ens160 ipv4.addresses 172.168.2.2/27 ipv4.gateway 172.168.2.1 ipv4.method manual
    nmcli con up ens160

    nmcli con mod ens192 ipv4.addresses 192.168.30.1/28 ipv4.method manual
    nmcli con up ens192

    # GRE
    nmcli con add type ip-tunnel ip-tunnel.mode gre con-name tun1 ifname tun1 remote 172.168.1.2 local 172.168.2.2
    nmcli con mod tun1 ipv4.addresses 10.10.10.2/30
    nmcli con up tun1
fi

# NAT
cat > /etc/nftables/router.nft <<EOF
table inet nat {
 chain POSTROUTING {
  type nat hook postrouting priority srcnat;
  oifname "ens160" masquerade
 }
}
EOF
echo 'include "/etc/nftables/router.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables

# User
useradd net_admin
echo "P@ssw0rd" | passwd --stdin net_admin
echo 'net_admin ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# FRR OSPF
dnf install frr -y
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr

timedatectl set-timezone Europe/Moscow

echo "$TYPE router configured"