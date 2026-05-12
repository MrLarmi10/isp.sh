#!/bin/bash
# br-srv_setup.sh — этап 1: установка всех пакетов, этап 2: настройка

set -e

# ============================================
# ЭТАП 1: Установка всех необходимых пакетов
# ============================================
echo "=== ЭТАП 1: Установка пакетов ==="


# Установка пакетов Samba DC
dnf install -y samba samba-client samba-dc bind bind-utils

# Установка Ansible (надёжными способами)
echo "=== Установка Ansible ==="
if dnf install -y ansible-core; then
    ANSIBLE_INSTALLED=1
elif dnf install -y epel-release && dnf install -y ansible; then
    ANSIBLE_INSTALLED=1
else
    echo "Пробуем установить Ansible через pip3..."
    dnf install -y python3-pip
    pip3 install ansible
    export PATH=$PATH:~/.local/bin
    ANSIBLE_INSTALLED=1
fi

# Установка Docker и docker-compose
dnf install -y docker docker-compose

# Включение и запуск Docker (чтобы можно было загружать образы)
systemctl enable docker
systemctl start docker

# Остановка и маскировка systemd-resolved (ещё до настройки Samba)
systemctl mask systemd-resolved 2>/dev/null || true
systemctl stop systemd-resolved 2>/dev/null || true

# ============================================
# ЭТАП 2: Настройка сервисов
# ============================================
echo "=== ЭТАП 2: Настройка сервисов ==="

# 1. Изменение порта SSH на 2026
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

# 2. Настройка Samba DC
rm -f /etc/samba/smb.conf
samba-tool domain provision --use-rfc2307 \
    --realm=AU-TEAM.IRPO \
    --domain=AU-TEAM \
    --adminpass='P@ssword' \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --option="bind interfaces only=no"

systemctl enable samba --now

# Настройка resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "search au-team.irpo" >> /etc/resolv.conf

# 3. Создание пользователей и группы
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

# 4. Настройка Ansible (инвентарь)
mkdir -p /etc/ansible
cat > /etc/ansible/hosts <<EOF
[servers]
HQ-SRV ansible_host=192.168.1.2 ansible_user=root ansible_ssh_pass=P@ssword ansible_ssh_port=2026
HQ-CLI ansible_host=192.168.2.2 ansible_user=User ansible_ssh_pass=P@ssword
HQ-RTR ansible_host=172.16.1.2 ansible_user=root ansible_ssh_pass=P@ssword
BR-RTR ansible_host=172.16.2.2 ansible_user=root ansible_ssh_pass=P@ssword
EOF

# Проверка ping (только если ansible установлен)
if command -v ansible &>/dev/null; then
    ansible all -m ping -i /etc/ansible/hosts || echo "Предупреждение: не все хосты доступны для ping."
else
    echo "Предупреждение: Ansible не установлен, проверка ping пропущена."
fi

# 5. Монтирование ISO и импорт Docker-образов
ISO_MOUNT="/mnt/iso"
mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    for dev in /dev/sr0 /dev/cdrom /dev/sr1; do
        if [ -b "$dev" ]; then
            mount "$dev" "$ISO_MOUNT" && break
        fi
    done
fi

if [ -d "$ISO_MOUNT/docker" ]; then
    docker load -i "$ISO_MOUNT/docker/site_latest.tar" || echo "Не удалось загрузить site_latest.tar"
    docker load -i "$ISO_MOUNT/docker/postgresql_latest.tar" || echo "Не удалось загрузить postgresql_latest.tar"
else
    echo "Предупреждение: образы Docker не найдены в ISO."
fi

# 6. Создание docker-compose.yml и запуск стека
mkdir -p /opt/testapp
cat > /opt/testapp/docker-compose.yml <<EOF
version: '3'
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

docker-compose -f /opt/testapp/docker-compose.yml up -d

echo "BR-SRV полностью настроен."