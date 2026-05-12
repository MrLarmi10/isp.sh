#!/bin/bash
# hq-srv_setup.sh

set -e

# Изменение порта SSH
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

# RAID1 автоматический поиск дисков
echo "Поиск двух свободных дисков для RAID1..."
ROOT_DEV=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//')
DISKS=()
for dev in /dev/sd[a-z] /dev/vd[a-z] /dev/nvme[0-9]n[0-9]; do
    [ -b "$dev" ] || continue
    [[ "$dev" == "$ROOT_DEV"* ]] && continue
    ls ${dev}[0-9]* 2>/dev/null | grep -q . && continue
    DISKS+=("$dev")
done
if [ ${#DISKS[@]} -lt 2 ]; then
    echo "Ошибка: найдено менее двух свободных дисков. Найдено: ${DISKS[@]}"
    exit 1
fi
DISK1="${DISKS[0]}"
DISK2="${DISKS[1]}"
echo "Будут использованы диски: $DISK1 и $DISK2"

mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 "$DISK1" "$DISK2"
mdadm --detail --scan --verbose >> /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid1
echo '/dev/md0 /raid1 ext4 defaults 0 0' >> /etc/fstab
mount -av

# NFS
dnf install -y nfs-utils
mkdir -p /raid1/nfs
echo '/raid1/nfs 192.168.2.0/28(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
systemctl enable --now nfs-server
exportfs -a

# Apache + MariaDB
dnf install -y httpd mariadb-server mariadb php php-mysqlnd
systemctl enable --now mariadb httpd

# Импорт базы данных (исправленные кавычки и имя файла)
mysql -uroot -e "CREATE DATABASE webdb;"
mysql -uroot webdb < /root/web/dump.sql
mysql -uroot -e "CREATE USER 'webserver'@'localhost' IDENTIFIED BY 'P@sswOrd';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON webdb.* TO 'webserver'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"

# Копирование файлов приложения
cp /root/web/index.php /var/www/html/
cp /root/web/*.jpg /var/www/html/ 2>/dev/null || true
sed -i "s/'\$db_user', .*/'\$db_user', 'webserver');/" /var/www/html/index.php
sed -i "s/'\$db_pass', .*/'\$db_pass', 'P@sswOrd');/" /var/www/html/index.php
sed -i "s/'\$db_name', .*/'\$db_name', 'webdb');/" /var/www/html/index.php

chown -R apache:apache /var/www/html
systemctl restart httpd

# SELinux
if command -v setsebool &>/dev/null; then
    setsebool -P httpd_can_network_connect_db 1
    setsebool -P nfs_export_all_rw 1
    restorecon -R /var/www/html /raid1
fi

echo "Настройка HQ-SRV успешно завершена."