#!/bin/bash
set -e

# Переменные
HQ_CLI_IP="10.0.1.20"        # IP клиента HQ-CLI
ISP_NTP_IP="192.168.0.254"   # IP ISP (NTP сервер)
DISK1="/dev/sdb"
DISK2="/dev/sdc"
ISO_MOUNT="/mnt/iso"

echo "=== Настройка HQ-SRV: RAID1, NFS, Apache+MariaDB, NTP ==="

# Установка ПО

dnf install -y mdadm nfs-kernel-server apache2 mariadb-server php libapache2-mod-php php-mysql chrony wget

# --- RAID1 (md0) из двух дисков ---
# Создаём массив (подтверждение перезаписи суперблоков)
mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 $DISK1 $DISK2 --force
# Сохраняем конфигурацию
mkdir -p /etc/mdadm
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u

# Создаём файловую систему ext4
mkfs.ext4 /dev/md0

# Монтируем и добавляем в fstab
mkdir -p /raid1
mount /dev/md0 /raid1
echo "/dev/md0 /raid1 ext4 defaults 0 0" >> /etc/fstab

# --- Настройка NFS ---
mkdir -p /raid1/nfs
cat >> /etc/exports <<EOF
/raid1/nfs $HQ_CLI_IP(rw,sync,no_subtree_check)
EOF

exportfs -a
systemctl restart nfs-kernel-server

# --- Веб-приложение (Apache + MariaDB) ---
# Монтируем образ Additional.iso (если не смонтирован)
if ! mountpoint -q $ISO_MOUNT; then
    mkdir -p $ISO_MOUNT
    mount /dev/cdrom $ISO_MOUNT || mount -o loop /path/to/Additional.iso $ISO_MOUNT
fi

# Копируем файлы приложения
cp -r $ISO_MOUNT/web/* /var/www/html/

# Настраиваем MariaDB
systemctl start mariadb
mysql <<EOF
CREATE DATABASE webdb;
USE webdb;
SOURCE $ISO_MOUNT/web/dump.sql;
CREATE USER 'webserver'@'localhost' IDENTIFIED BY 'P@sswOrd';
GRANT ALL PRIVILEGES ON webdb.* TO 'webserver'@'localhost';
FLUSH PRIVILEGES;
EOF

# Правим index.php – вставляем учётные данные
sed -i "s/'db_user', '.*'/'db_user', 'webserver'/" /var/www/html/index.php
sed -i "s/'db_password', '.*'/'db_password', 'P@sswOrd'/" /var/www/html/index.php
sed -i "s/'db_name', '.*'/'db_name', 'webdb'/" /var/www/html/index.php

# Включаем и перезапускаем Apache
systemctl enable apache2
systemctl restart apache2

# --- NTP клиент ---
cat > /etc/chrony/chrony.conf <<EOF
server $ISP_NTP_IP iburst
makestep 1 3
leapsectz right/UTC
EOF

systemctl restart chrony
systemctl enable chrony

echo "=== Настройка HQ-SRV завершена ==="