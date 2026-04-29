#!/bin/bash
set -e

echo "=== Настройка HQ-SRV: RAID1, NFS, веб-приложение (apache+mariadb), SSH порт 2026, NTP клиент ==="

apt update
apt install -y mdadm nfs-kernel-server apache2 mariadb-server mariadb-client php php-mysql chrony openssh-server wget

# 1. RAID1 из /dev/sdb и /dev/sdc
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc --force
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u
mkfs.ext4 /dev/md0
mkdir -p /raid1
mount /dev/md0 /raid1
echo "/dev/md0 /raid1 ext4 defaults 0 0" >> /etc/fstab

# 2. NFS директория и экспорт
mkdir -p /raid1/nfs
chmod 777 /raid1/nfs
echo "/raid1/nfs 192.168.1.11(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -a
systemctl enable nfs-kernel-server
systemctl restart nfs-kernel-server

# 3. SSH на порт 2026
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart ssh

# 4. MariaDB и импорт дампа (предполагается, что Additional.iso смонтирован в /mnt/iso)
mkdir -p /mnt/iso
mount -o loop /path/to/Additional.iso /mnt/iso   # замените на реальный путь к ISO
mysql -e "CREATE DATABASE webdb;"
mysql webdb < /mnt/iso/web/dump.sql
mysql -e "CREATE USER 'webserver'@'localhost' IDENTIFIED BY 'P@sswOrd';"
mysql -e "GRANT ALL PRIVILEGES ON webdb.* TO 'webserver'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# 5. Apache и копирование PHP файлов
cp /mnt/iso/web/*.php /var/www/html/
cp -r /mnt/iso/web/images /var/www/html/
sed -i 's/DB_PASSWORD/'"P@sswOrd"'/' /var/www/html/index.php   # пример правки, зависит от index.php
systemctl enable apache2
systemctl restart apache2

# 6. NTP клиент (сервер ISP)
cat > /etc/chrony/chrony.conf <<EOF
server 192.168.1.254 iburst
pool 0.pool.ntp.org iburst
EOF
systemctl enable chrony
systemctl restart chrony

umount /mnt/iso

echo "=== Настройка HQ-SRV завершена ==="