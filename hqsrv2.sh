#!/bin/bash
# hq-srv_setup.sh - без настройки IP

set -e

# Изменение порта SSH на 2026 (не настройка IP)
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

# RAID1 из двух дисков (sdb, sdc)
dnf install -y mdadm e2fsprogs
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc --force --run
mdadm --detail --scan >> /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid1
echo '/dev/md0 /raid1 ext4 defaults 0 0' >> /etc/fstab
mount /raid1

# NFS
dnf install -y nfs-utils
mkdir -p /raid1/nfs
echo '/raid1/nfs 192.168.2.0/28(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
systemctl enable --now nfs-server
exportfs -a

# Веб-сервер Apache + MariaDB
dnf install -y httpd mariadb-server mariadb php php-mysqlnd
systemctl enable --now mariadb httpd

# Импорт базы данных (файл dump.sql предполагается в /root/web)
mysql -e "CREATE DATABASE webdb;"
mysql webdb < /root/web/dump.sql
mysql -e "CREATE USER 'webserver'@'localhost' IDENTIFIED BY 'P@sswOrd';"
mysql -e "GRANT ALL PRIVILEGES ON webdb.* TO 'webserver'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Копирование файлов приложения
cp /root/web/index.php /var/www/html/
cp /root/web/*.jpg /var/www/html/ 2>/dev/null || true
# Настройка подключения в index.php
sed -i "s/'\$db_user', .*/'\$db_user', 'webserver');/" /var/www/html/index.php
sed -i "s/'\$db_pass', .*/'\$db_pass', 'P@sswOrd');/" /var/www/html/index.php
sed -i "s/'\$db_name', .*/'\$db_name', 'webdb');/" /var/www/html/index.php

chown -R apache:apache /var/www/html
systemctl restart httpd

# SELinux (если включён)
if command -v setsebool &>/dev/null; then
    setsebool -P httpd_can_network_connect_db 1
    setsebool -P nfs_export_all_rw 1
    restorecon -R /var/www/html /raid1
fi