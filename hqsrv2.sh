#!/bin/bash
# hq-srv_setup.sh
# Полная настройка HQ-SRV: RAID1, NFS, Apache, MariaDB, веб-приложение

set -e

# 1. Изменение порта SSH на 2026
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

# 2. Создание RAID1 (как на фото, но уровень 1 и точки монтирования /raid1)
#    Предполагаются диски /dev/sdb и /dev/sdc по 1 ГБ
mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc
mdadm --detail --scan --verbose >> /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid1
echo '/dev/md0 /raid1 ext4 defaults 0 0' >> /etc/fstab
mount -av   # монтирует всё из fstab, включая /raid1

# 3. NFS-расшаривание каталога /raid1/nfs
dnf install -y nfs-utils
mkdir -p /raid1/nfs
echo '/raid1/nfs 192.168.2.0/28(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
systemctl enable --now nfs-server
exportfs -a

# 4. Веб-сервер Apache + MariaDB
dnf install -y httpd mariadb-server mariadb php php-mysqlnd
systemctl enable --now mariadb httpd

# Импорт базы данных (dump.sql должен лежать в /root/web)
mysql -e "CREATE DATABASE webdb;"
mysql webdb < /root/web/dump.sql
mysql -e "CREATE USER 'webserver'@'localhost' IDENTIFIED BY 'P@sswOrd';"
mysql -e "GRANT ALL PRIVILEGES ON webdb.* TO 'webserver'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Копирование файлов приложения
cp /root/web/index.php /var/www/html/
cp /root/web/*.jpg /var/www/html/ 2>/dev/null || true
# Правка учётных данных в index.php
sed -i "s/'\$db_user', .*/'\$db_user', 'webserver');/" /var/www/html/index.php
sed -i "s/'\$db_pass', .*/'\$db_pass', 'P@sswOrd');/" /var/www/html/index.php
sed -i "s/'\$db_name', .*/'\$db_name', 'webdb');/" /var/www/html/index.php

chown -R apache:apache /var/www/html
systemctl restart httpd

# 5. Настройка SELinux (если включён)
if command -v setsebool &>/dev/null; then
    setsebool -P httpd_can_network_connect_db 1
    setsebool -P nfs_export_all_rw 1
    restorecon -R /var/www/html /raid1
fi

echo "Настройка HQ-SRV завершена."