#!/bin/bash
# hq-srv_setup.sh - устойчивый к ошибкам скрипт настройки HQ-SRV

set -euo pipefail  # жёсткий режим, но ошибки монтирования перехватываются

# === 1. Изменение порта SSH (всегда выполняется) ===
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd || true

# === 2. RAID1 (автоматический поиск свободных дисков) ===
echo "=== Настройка RAID1 ==="
ROOT_DEV=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//')
DISKS=()
for dev in /dev/sd[a-z] /dev/vd[a-z] /dev/nvme[0-9]n[0-9]; do
    [ -b "$dev" ] || continue
    if [[ "$dev" == "$ROOT_DEV"* ]]; then continue; fi
    if ls ${dev}[0-9]* 2>/dev/null | grep -q .; then continue; fi
    DISKS+=("$dev")
done

if [ ${#DISKS[@]} -ge 2 ]; then
    DISK1="${DISKS[0]}"
    DISK2="${DISKS[1]}"
    echo "Используем диски: $DISK1 и $DISK2"
    mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 "$DISK1" "$DISK2" || echo "RAID уже существует?"
    mdadm --detail --scan --verbose >> /etc/mdadm.conf 2>/dev/null || true
    mkfs.ext4 /dev/md0 || true
    mkdir -p /raid1
    if ! grep -q '/dev/md0' /etc/fstab; then
        echo '/dev/md0 /raid1 ext4 defaults 0 0' >> /etc/fstab
    fi
    mount -av || true
else
    echo "Не найдено двух свободных дисков для RAID. Пропускаем."
fi

# === 3. NFS ===
echo "=== Настройка NFS ==="
dnf install -y nfs-utils || true
mkdir -p /raid1/nfs
if ! grep -q '/raid1/nfs' /etc/exports; then
    echo '/raid1/nfs 192.168.2.0/28(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
fi
systemctl enable --now nfs-server || true
exportfs -a || true

# === 4. Веб-сервер и MariaDB ===
echo "=== Установка Apache, MariaDB, PHP ==="
dnf install -y httpd mariadb-server mariadb php php-mysqlnd || true
systemctl enable --now mariadb httpd || true

# === 5. Копирование файлов приложения (ISO или ручное) ===
echo "=== Поиск файлов веб-приложения ==="
TARGET_DIR="/root/web"
mkdir -p "$TARGET_DIR"
PHP_SRC=""
SQL_SRC=""

# Функция рекурсивного поиска файлов в заданном каталоге
find_files() {
    local dir="$1"
    php_src=$(find "$dir" -type f -name "index.php" -print -quit 2>/dev/null || true)
    sql_src=$(find "$dir" -type f -name "dump.sql" -print -quit 2>/dev/null || true)
}

# Пытаемся смонтировать ISO
ISO_MOUNT="/mnt/iso"
mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    # Ищем устройство cdrom
    for dev in /dev/sr0 /dev/cdrom /dev/sr1 /dev/sr2; do
        if [ -b "$dev" ]; then
            echo "Монтирование $dev в $ISO_MOUNT"
            mount "$dev" "$ISO_MOUNT" 2>/dev/null && break
        fi
    done
fi

# Если ISO смонтирован, ищем файлы внутри
if mountpoint -q "$ISO_MOUNT"; then
    echo "ISO смонтирован, ищем index.php и dump.sql..."
    find_files "$ISO_MOUNT"
    if [ -n "$php_src" ] && [ -n "$sql_src" ]; then
        echo "Файлы найдены в ISO"
        cp "$php_src" "$TARGET_DIR/index.php"
        cp "$sql_src" "$TARGET_DIR/dump.sql"
        # Копируем также изображения
        find "$ISO_MOUNT" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \) -exec cp {} "$TARGET_DIR/" \; 2>/dev/null || true
    else
        echo "В ISO не найдены index.php или dump.sql"
    fi
else
    echo "ISO не смонтирован (устройство не найдено)."
fi

# Если файлы не скопировались, проверим ручной каталог /root/web
if [ ! -f "$TARGET_DIR/index.php" ] || [ ! -f "$TARGET_DIR/dump.sql" ]; then
    echo "Проверяем /root/web на наличие файлов..."
    if [ -f /root/web/index.php ] && [ -f /root/web/dump.sql ]; then
        echo "Файлы найдены в /root/web"
        cp /root/web/index.php "$TARGET_DIR/" 2>/dev/null || true
        cp /root/web/dump.sql "$TARGET_DIR/" 2>/dev/null || true
    else
        echo "ВНИМАНИЕ: файлы index.php или dump.sql отсутствуют. Будет создана заглушка."
        # Создаём заглушку index.php
        cat > "$TARGET_DIR/index.php" <<'EOF'
<?php
echo "<h1>Веб-приложение не установлено</h1>";
echo "<p>Файлы index.php или dump.sql не найдены в ISO или в /root/web.</p>";
?>
EOF
        # Создаём пустой dump.sql, чтобы импорт не упал
        touch "$TARGET_DIR/dump.sql"
    fi
fi

# === 6. Импорт базы данных (только если dump.sql не пуст) ===
echo "=== Настройка базы данных ==="
if [ -s "$TARGET_DIR/dump.sql" ]; then
    mysql -uroot -e "CREATE DATABASE webdb;" 2>/dev/null || true
    mysql -uroot webdb < "$TARGET_DIR/dump.sql" 2>/dev/null || echo "Импорт dump.sql не удался (возможно, пустой файл)"
    mysql -uroot -e "CREATE USER 'webserver'@'localhost' IDENTIFIED BY 'P@sswOrd';" 2>/dev/null || true
    mysql -uroot -e "GRANT ALL PRIVILEGES ON webdb.* TO 'webserver'@'localhost';" 2>/dev/null || true
    mysql -uroot -e "FLUSH PRIVILEGES;" 2>/dev/null || true
else
    echo "Файл dump.sql пуст или отсутствует, импорт БД пропущен."
fi

# === 7. Копирование в Apache ===
echo "=== Размещение файлов в Apache ==="
cp "$TARGET_DIR/index.php" /var/www/html/ 2>/dev/null || true
cp "$TARGET_DIR"/*.jpg /var/www/html/ 2>/dev/null || true
cp "$TARGET_DIR"/*.png /var/www/html/ 2>/dev/null || true

# Настраиваем подключение к БД в index.php (если файл содержит переменные)
if [ -f /var/www/html/index.php ]; then
    sed -i "s/'\$db_user', .*/'\$db_user', 'webserver');/" /var/www/html/index.php 2>/dev/null || true
    sed -i "s/'\$db_pass', .*/'\$db_pass', 'P@sswOrd');/" /var/www/html/index.php 2>/dev/null || true
    sed -i "s/'\$db_name', .*/'\$db_name', 'webdb');/" /var/www/html/index.php 2>/dev/null || true
fi

chown -R apache:apache /var/www/html 2>/dev/null || true
systemctl restart httpd 2>/dev/null || true

# === 8. SELinux (без критичности) ===
if command -v setsebool &>/dev/null; then
    setsebool -P httpd_can_network_connect_db 1 2>/dev/null || true
    setsebool -P nfs_export_all_rw 1 2>/dev/null || true
    restorecon -R /var/www/html /raid1 2>/dev/null || true
fi

echo "=== Настройка HQ-SRV завершена ==="
exit 0