#!/bin/bash
set -e

echo "=== Настройка HQ-SRV: RAID1, NFS, Apache+MariaDB, PHP, SSH 2026, NTP ==="

dnf makecache
dnf install -y mdadm nfs-utils httpd mariadb-server mariadb php php-mysqlnd chrony openssh-server wget

mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc --force
mdadm --detail --scan >> /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid1
mount /dev/md0 /raid1
echo "/dev/md0 /raid1 ext4 defaults 0 0" >> /etc/fstab

mkdir -p /raid1/nfs
chmod 777 /raid1/nfs
echo "/raid1/nfs 192.168.1.11(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -a
systemctl enable nfs-server
systemctl restart nfs-server

sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

mkdir -p /mnt/iso
mount -o loop /path/to/Additional.iso /mnt/iso    # замените путь

systemctl enable mariadb
systemctl start mariadb
mysql -e "CREATE DATABASE webdb;"
mysql webdb < /mnt/iso/web/dump.sql
mysql -e "CREATE USER 'webserver'@'localhost' IDENTIFIED BY 'P@sswOrd';"
mysql -e "GRANT ALL PRIVILEGES ON webdb.* TO 'webserver'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

cp /mnt/iso/web/*.php /var/www/html/
cp -r /mnt/iso/web/images /var/www/html/
sed -i 's/DB_PASSWORD/'"P@sswOrd"'/' /var/www/html/index.php

systemctl enable httpd
systemctl restart httpd

cat > /etc/chrony.conf <<EOF
server 192.168.1.254 iburst
pool 0.pool.ntp.org iburst
EOF
systemctl enable chronyd
systemctl restart chronyd

umount /mnt/iso
echo "=== Настройка HQ-SRV завершена ==="