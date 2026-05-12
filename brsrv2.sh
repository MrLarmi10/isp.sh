#!/bin/bash
# br-srv_setup.sh — сначала установка всех пакетов, потом настройка

set -e

# ============================================
# 1. Установка всех пакетов (без конфигурации)
# ============================================


# Устанавливаем пакеты Samba
dnf install -y samba samba-client samba-dc bind bind-utils

# Устанавливаем Ansible (через EPEL или ansible-core)
dnf install -y epel-release || true
dnf install -y ansible-core || dnf install -y ansible || true

# Устанавливаем Docker и docker-compose (из стандартных репозиториев)
dnf install -y docker-ce docker-ce-cli docker-compose || true

# ============================================
# 2. Настройка SSH
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

# Возвращаем локальный DNS для работы домена
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
# 4. Настройка Ansible
# ============================================
echo "=== Настройка Ansible ==="
mkdir -p /etc/ansible
cat > /etc/ansible/hosts <<EOF
[servers]
HQ-SRV ansible_host=192.168.1.2 ansible_user=root ansible_ssh_pass=P@ssword ansible_ssh_port=2026
HQ-CLI ansible_host=192.168.2.2 ansible_user=User ansible_ssh_pass=P@ssword
HQ-RTR ansible_host=172.16.1.2 ansible_user=root ansible_ssh_pass=P@ssword
BR-RTR ansible_host=172.16.2.2 ansible_user=root ansible_ssh_pass=P@ssword
EOF

if command -v ansible &>/dev/null && command -v sshpass &>/dev/null; then
    ansible all -m ping -i /etc/ansible/hosts || echo "Предупреждение: не все хосты доступны."
else
    echo "Ошибка: ansible или sshpass не установлены."
    exit 1
fi

# ============================================
# 5. Настройка Docker и приложения testapp
# ============================================
echo "=== Настройка Docker и testapp ==="
systemctl enable --now docker

# Монтируем ISO, если есть
ISO_MOUNT="/mnt/iso"
mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    for dev in /dev/sr0 /dev/cdrom /dev/sr1; do
        if [ -b "$dev" ]; then
            mount "$dev" "$ISO_MOUNT" && break
        fi
    done
fi

# Импортируем образы из ISO
if [ -d "$ISO_MOUNT/docker" ]; then
    for tarfile in "$ISO_MOUNT/docker"/*.tar; do
        [ -f "$tarfile" ] && docker load -i "$tarfile"
    done
fi

# Приводим имена образов
PG_IMG=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "postgres|postgresql" | head -1)
[ -n "$PG_IMG" ] && [ "$PG_IMG" != "postgresql_latest" ] && docker tag "$PG_IMG" postgresql_latest

SITE_IMG=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "site|testapp" | head -1)
[ -n "$SITE_IMG" ] && [ "$SITE_IMG" != "site_latest" ] && docker tag "$SITE_IMG" site_latest

# Создаём docker-compose.yml
mkdir -p /opt/testapp
cat > /opt/testapp/docker-compose.yml <<'EOF'
services:
  db:
    image: postgresql_latest
    container_name: db
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: testc
      POSTGRES_PASSWORD: P@sswOrd
    volumes:
      - db_data:/var/lib/postgresql/data
  testapp:
    image: site_latest
    container_name: testapp
    ports:
      - "80:8080"
    environment:
      DB_HOST: db
      DB_PORT: 5432
      DB_NAME: testdb
      DB_USER: testc
      DB_PASSWORD: P@sswOrd
    depends_on:
      - db
volumes:
  db_data:
EOF

# Запускаем стек
if docker image inspect postgresql_latest &>/dev/null && docker image inspect site_latest &>/dev/null; then
    docker-compose -f /opt/testapp/docker-compose.yml up -d
else
    echo "Не удалось найти оба образа. Пропускаем запуск."
fi

echo "=== Настройка BR-SRV завершена ==="