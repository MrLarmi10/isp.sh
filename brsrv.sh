#!/bin/bash

hostnamectl set-hostname br-srv.au-team.irpo
timedatectl set-timezone Europe/Moscow

# IP
nmcli con mod ens160 ipv4.addresses 192.168.30.2/28 ipv4.gateway 192.168.30.1 ipv4.dns 192.168.10.2 ipv4.method manual
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

echo "BR-SRV configured"