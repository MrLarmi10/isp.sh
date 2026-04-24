#!/bin/bash

# =====================================================
# МОДУЛЬ 2: Настройка HQ-SRV
# - RAID 1 (md0) из двух дисков
# - NFS сервер (/raid/nfs)
# - Web (Apache + MariaDB + PHP)
# =====================================================

set -e

echo "=== МОДУЛЬ 2: Настройка HQ-SRV ==="

# 1. RAID 1 (md0)
# Предполагаем диски /dev/sdb и /dev/sdc
if [ -b /dev/sdb ] && [ -b /dev/sdc ]; then
    dnf install -y mdadm
    
    # Создание RAID 1
    mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc --force --run
    
    # Создание файловой системы ext4
    mkfs.ext4 -F /dev/md0
    
    # Создание точки монтирования
    mkdir -p /raid
    
    # Монтирование
    mount /dev/md0 /raid
    
    # Добавление в fstab
    echo "/dev/md0 /raid ext4 defaults 0 0" >> /etc/fstab
    
    # Сохранение конфигурации mdadm
    mdadm --detail --scan >> /etc/mdadm.conf
else
    echo "Диски /dev/sdb и /dev/sdc не найдены. RAID пропущен."
fi

# 2. NFS сервер
dnf install -y nfs-utils

# Создание директории для NFS
mkdir -p /raid/nfs
chmod 755 /raid/nfs

# Настройка экспорта
cat >> /etc/exports <<EOF
/raid/nfs 192.168.20.0/27(rw,sync,no_root_squash,subtree_check)
EOF

# Запуск NFS
systemctl enable --now nfs-server
exportfs -a

# 3. Web сервер (Apache + MariaDB + PHP)
dnf install -y httpd mariadb-server php php-mysqlnd

systemctl enable --now mariadb
systemctl enable --now httpd

# Настройка БД
mysql <<'EOF'
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'webc'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'webc'@'localhost';
FLUSH PRIVILEGES;
EOF

# Импорт дампа (если есть)
if [ -f /root/dump.sql ]; then
    mysql webdb < /root/dump.sql
    echo "Дамп импортирован"
fi

# Копирование файлов веб-приложения (предполагаем смонтированный Additional.iso)
ISO_MOUNT="/mnt/iso"
if [ -d "$ISO_MOUNT/web" ]; then
    cp "$ISO_MOUNT/web/index.php" /var/www/html/ 2>/dev/null || true
    cp -r "$ISO_MOUNT/web/images" /var/www/html/ 2>/dev/null || true
fi

# Настройка index.php (учетные данные)
cat > /var/www/html/index.php <<'EOF'
<?php
$host = 'localhost';
$user = 'webc';
$pass = 'P@ssw0rd';
$dbname = 'webdb';

$conn = mysqli_connect($host, $user, $pass, $dbname);

if (!$conn) {
    die("Ошибка подключения к БД: " . mysqli_connect_error());
}
echo "Подключение к БД успешно!<br>";
echo "Сервер: " . gethostname() . "<br>";
?>
EOF

systemctl restart httpd

echo "=== МОДУЛЬ 2: HQ-SRV готова ==="