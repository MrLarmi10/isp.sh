#!/bin/bash
# br-srv_setup.sh — исправлен с учётом ошибок Ansible и Docker

set -e

sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config




set -e

# ============================================
# 0. Настройка chrony
# ============================================

echo "=== Установка chrony ==="
dnf install -y chrony

echo "=== Настройка /etc/chrony.conf ==="
cp /etc/chrony.conf /etc/chrony.conf.bak 2>/dev/null || true
sed -i 's/^server/#server/' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf

systemctl restart chronyd
systemctl enable chronyd

echo "=== Проверка синхронизации ==="
chronyc sources -v

echo "=== Готово ==="

# ============================================
# 1. Установка пакетов (по командам пользователя)
# ============================================
echo "=== Установка пакетов ==="

# Удаляем podman-docker, если есть конфликт
if rpm -q podman-docker &>/dev/null; then
    echo "Удаляем podman-docker..."
    dnf remove -y podman-docker
fi

# Устанавливаем пакеты Samba
dnf install -y samba samba-client samba-dc bind bind-utils

# Устанавливаем Ansible и sshpass (команда пользователя)
dnf install -y ansible sshpass || true

# Устанавливаем Docker и docker-compose (команда пользователя)
dnf install -y docker-ce docker-ce-cli docker-compose || true

# Если docker не установился, пробуем стандартный пакет docker
if ! command -v docker &>/dev/null; then
    dnf install -y docker docker-compose || true
fi

# ============================================
# 2. Настройка SSH (порт 2026)
# ============================================
echo "=== Настройка SSH ==="
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

# ============================================
# 3. Настройка Samba DC
# ============================================
echo "=== Настройка контроллера домена Samba ==="
systemctl mask systemd-resolved
systemctl stop systemd-resolved

rm -f /etc/samba/smb.conf
samba-tool domain provision --use-rfc2307 \
    --realm=AU-TEAM.IRPO \
    --domain=AU-TEAM \
    --adminpass='P@ssword' \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --option="bind interfaces only=no"

systemctl enable samba --now

echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "search au-team.irpo" >> /etc/resolv.conf

# Создание пользователей и группы
for i in {1..5}; do
    samba-tool user create sidehquser$i \
        --given-name=Side \
        --surname=HQUser$i \
        --password='P@ssword'
done
samba-tool group add sidehq
for i in {1..5}; do
    samba-tool group addmembers sidehq sidehquser$i
done
samba-tool computer add HQ-CLI --password='P@ssword'

# ============================================
# 4. Настройка Ansible (исправление ошибок подключения)
# ============================================
echo "=== Настройка Ansible ==="

# Отключаем проверку host key для всех хостов
mkdir -p /etc/ansible
cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
host_key_checking = False
EOF

# Создаём инвентарь с параметрами для игнорирования ключей хостов
echo "=== Настройка Ansible ==="

# Устанавливаем ansible и sshpass (по вашей команде)
dnf install -y ansible sshpass || true



# Настройка ansible.cfg (отключаем проверку ключей хостов)
mkdir -p /etc/ansible
cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
host_key_checking = False
EOF

# Инвентарь с использованием SSH-ключа
cat > /etc/ansible/hosts <<EOF
[servers]
HQ-SRV ansible_host=192.168.1.2 ansible_user=sshuser ansible_password=P@ssw0rd
HQ-CLI ansible_host=192.168.2.2 ansible_user=user ansible_password=P@ssword
HQ-RTR ansible_host=172.16.1.1 ansible_user=net_admin ansible_password=P@ssw0rd
BR-RTR ansible_host=192.168.4.1 ansible_user=net_admin ansible_password=P@ssw0rd
EOF

# Проверка подключения
if command -v ansible &>/dev/null; then
    ansible all -m ping -i /etc/ansible/hosts || echo "Предупреждение: не все хосты доступны. Проверьте, что SSH-ключ скопирован."
else
    echo "Ошибка: ansible не установлен."
    exit 1
fi


# Проверяем подключение (теперь ошибка «Host Key checking is enabled» должна исчезнуть)
if command -v ansible &>/dev/null && command -v sshpass &>/dev/null; then
    ansible all -m ping -i /etc/ansible/hosts || echo "Предупреждение: не все хосты доступны. Проверьте пароли и настройки SSH."
else
    echo "Ошибка: ansible или sshpass не установлены."
    exit 1
fi

# ============================================
# 5. Настройка Docker и приложения testapp
# ============================================
echo "=== Настройка Docker и testapp ==="
systemctl enable --now docker

# Монтируем ISO, если есть (игнорируем ошибки, если нет носителя)
ISO_MOUNT="/mnt/iso"
mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    for dev in /dev/sr0 /dev/cdrom /dev/sr1; do
        if [ -b "$dev" ]; then
            mount "$dev" "$ISO_MOUNT" 2>/dev/null && break
        fi
    done
fi

# Импортируем образы из ISO, если каталог существует
if [ -d "$ISO_MOUNT/docker" ]; then
    for tarfile in "$ISO_MOUNT/docker"/*.tar; do
        [ -f "$tarfile" ] && docker load -i "$tarfile"
    done
else
    echo "Предупреждение: образы Docker не найдены в ISO. Пытаемся использовать локальные образы."
fi

# Если образов всё нет, можно попробовать найти в /root или другом месте
if ! docker image inspect site_latest &>/dev/null || ! docker image inspect postgresql_latest &>/dev/null; then
    echo "Поиск образов в /root/web или /root/docker..."
    for dir in /root/web /root/docker /opt/docker; do
        if [ -d "$dir" ]; then
            for tarfile in "$dir"/*.tar; do
                [ -f "$tarfile" ] && docker load -i "$tarfile"
            done
        fi
    done
fi

# Приводим имена образов к требуемым (если найдены похожие)
PG_IMG=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "postgres|postgresql" | head -1)
if [ -n "$PG_IMG" ] && [ "$PG_IMG" != "postgresql_latest" ]; then
    echo "Тегируем $PG_IMG как postgresql_latest"
    docker tag "$PG_IMG" postgresql_latest
fi

SITE_IMG=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "site|testapp" | head -1)
if [ -n "$SITE_IMG" ] && [ "$SITE_IMG" != "site_latest" ]; then
    echo "Тегируем $SITE_IMG как site_latest"
    docker tag "$SITE_IMG" site_latest
fi

echo "=== Настройка Docker и testapp ==="
systemctl enable --now docker

# Монтируем ISO (если есть)
ISO_MOUNT="/mnt/iso"
mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    mount /dev/sr0 "$ISO_MOUNT" 2>/dev/null || true
fi

# Импортируем образы из ISO (если там есть site_latest, mariadb и т.д.)
if [ -d "$ISO_MOUNT/docker" ]; then
    for tarfile in "$ISO_MOUNT/docker"/*.tar; do
        [ -f "$tarfile" ] && docker load -i "$tarfile"
    done
fi

# Приводим имена образов к требуемым (если загрузились site_latest или другие)
# Если в ISO образ называется site_latest, переименуем в site:latest
if docker image inspect site_latest &>/dev/null; then
    docker tag site_latest site:latest
fi
# Если есть postgresql_latest, но нужен mariadb, можно оставить как есть, но по фото нужен mariadb:10.11
# Пользователь сам обеспечит наличие образа mariadb:10.11 (либо из ISO, либо из репозитория)

# Создаём docker-compose.yml в точности как на скриншоте
mkdir -p /opt/testapp
cat > /opt/testapp/docker-compose.yml <<'EOF'
services:
  testapp:
    container_name: testapp
    image: site:latest
    restart: always
    ports:
      - "8080:8080"
    environment:
      DB_TYPE: db
      DB_HOST: "192.168.4.2"
      DB_NAME: mariadb
      DB_PORT: "3306"
      DB_USER: testc
      DB_PASS: P@ssword
    depends_on:
      - db
  db:
    container_name: db
    image: mariadb:10.11
    restart: always
    ports:
      - "3226:3226"
    environment:
      MARIADB_DATABASE: mariadb
      MARIADB_USER: testc
      MARIADB_PASSWORD: P@ssword
      MARIADB_ROOT_PASSWORD: P@ssword
EOF

# Запуск стека
docker-compose -f /opt/testapp/docker-compose.yml up -d

# Запускаем стек, если образы существуют
if docker image inspect postgresql_latest &>/dev/null && docker image inspect site_latest &>/dev/null; then
    docker-compose -f /opt/testapp/docker-compose.yml up -d
else
    echo "Не удалось найти образы postgresql_latest и/или site_latest. Пропускаем запуск."
    echo "Убедитесь, что образы загружены из ISO или импортированы вручную."
fi

echo "=== Настройка BR-SRV завершена ==="