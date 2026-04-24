#!/bin/bash

hostnamectl set-hostname hq-srv.au-team.irpo
timedatectl set-timezone Europe/Moscow

# IP VLAN10
nmcli con mod ens160 ipv4.addresses 192.168.10.2/26 ipv4.gateway 192.168.10.1 ipv4.dns 127.0.0.1 ipv4.method manual
nmcli con up ens160

# Пользователь
useradd sshuser -u 3026 -U
echo "P@ssw0rd" | passwd --stdin sshuser
echo 'sshuser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# SSH
sed -i 's/#Port 22/Port 3026/' /etc/ssh/sshd_config
echo "MaxAuthTries 2" >> /etc/ssh/sshd_config
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
echo "AllowUsers sshuser" >> /etc/ssh/sshd_config
echo "Authorized access only" > /etc/issue.net
systemctl restart sshd

# DNS server
dnf install -y bind bind-utils

sed -i 's/listen-on port 53.*/listen-on port 53 { any; };/' /etc/named.conf
sed -i 's/listen-on-v6 port 53.*/listen-on-v6 port 53 { none; };/' /etc/named.conf
sed -i 's/allow-query.*/allow-query     { any; };/' /etc/named.conf
sed -i 's/dnssec-validation yes;/dnssec-validation no;/' /etc/named.conf

cat >> /etc/named.conf <<EOF

zone "au-team.irpo" IN {
 type master;
 file "master/au-team.irpo.db";
};

zone "10.168.192.in-addr.arpa" IN {
 type master;
 file "master/192.168.10.db";
};
EOF

mkdir -p /var/named/master

cat > /var/named/master/au-team.irpo.db <<EOF
\$TTL 1D
@ IN SOA hq-srv.au-team.irpo. root.au-team.irpo. (
 1 1D 1H 1W 3H )
@ IN NS hq-srv.au-team.irpo.
hq-rtr IN A 192.168.10.1
hq-srv IN A 192.168.10.2
hq-cli IN A 192.168.20.2
br-rtr IN A 192.168.30.1
br-srv IN A 192.168.30.2
docker IN A 172.168.1.1
web IN A 172.168.2.1
EOF

cat > /var/named/master/192.168.10.db <<EOF
\$TTL 1D
@ IN SOA hq-srv.au-team.irpo. root.au-team.irpo. (
 1 1D 1H 1W 3H )
@ IN NS hq-srv.au-team.irpo.
2 IN PTR hq-srv.au-team.irpo.
1 IN PTR hq-rtr.au-team.irpo.
EOF

chown -R root:named /var/named/master
chmod 640 /var/named/master/*

named-checkconf
systemctl enable --now named

echo "HQ-SRV configured"