#!/bin/bash

# =====================================================
# МОДУЛЬ 2: Настройка BR-SRV
# - Samba DC (контроллер домена au-team.irpo)
# - Ansible (инвентарь, пинг всех машин)
# - Docker (mariadb + testapp)
# =====================================================

set -e

echo "=== МОДУЛЬ 2: Настройка BR-SRV ==="

# 1. Samba DC (контроллер домена)
dnf install -y samba samba-client samba-common samba-dc

# Остановка и отключение стандартных служб (если есть)
systemctl stop smb nmb 2>/dev/null || true
systemctl disable smb nmb 2>/dev/null || true

# Настройка DNS для Samba (используем внутренний DNS Samba)
# Предварительная настройка (продвижение домена)
cat > /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain
192.168.200.2 br-srv.au-team.irpo br-srv
EOF

# Провижн домена (интерактивно или с конфигом)
# Используем заранее подготовленный ответ
cat > /root/samba-provision.txt <<EOF
au-team.irpo
AU-TEAM
P@sswOrd
P@sswOrd
EOF

# Выполняем provision (неинтерактивно через stdin)
samba-tool domain provision --use-rfc2307 --interactive < /root/samba-provision.txt 2>/dev/null || \
samba-tool domain provision --domain=AU-TEAM --realm=au-team.irpo --adminpass='P@sswOrd' --server-role=dc --use-rfc2307

# Копирование керберос конфига
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Запуск Samba DC
systemctl enable samba
systemctl start samba

# Создание 5 пользователей hquser1-5
for i in {1..5}; do
    samba-tool user create hquser$i P@sswOrd
done

# Создание группы hq
samba-tool group add hq

# Добавление пользователей в группу hq
for i in {1..5}; do
    samba-tool group addmembers hq hquser$i
done

# Настройка права аутентификации на HQ-CLI (позже при вводе в домен)

# 2. Ansible
dnf install -y ansible

# Рабочий каталог /etc/ansible
mkdir -p /etc/ansible

# Файл инвентаря
cat > /etc/ansible/hosts <<'EOF'
[all]
hq-srv.au-team.irpo ansible_host=192.168.10.2 ansible_user=sshuser
hq-cli.au-team.irpo ansible_host=192.168.20.10 ansible_user=sshuser
hq-rtr.au-team.irpo ansible_host=192.168.10.1 ansible_user=net_admin
br-rtr.au-team.irpo ansible_host=192.168.200.1 ansible_user=net_admin

[servers]
hq-srv.au-team.irpo
br-srv.au-team.irpo

[routers]
hq-rtr.au-team.irpo
br-rtr.au-team.irpo

[clients]
hq-cli.au-team.irpo
EOF

# Настройка ansible.cfg
cat > /etc/ansible/ansible.cfg <<'EOF'
[defaults]
host_key_checking = False
inventory = /etc/ansible/hosts
remote_user = sshuser
EOF

# Генерация SSH ключа для ansible (если нет)
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
fi

# Копирование ключа на все машины (требует пароль)
echo "=== Копирование SSH ключа на все машины ==="
for host in 192.168.10.2 192.168.20.10 192.168.10.1 192.168.200.1; do
    sshpass -p 'P@sswOrd' ssh-copy-id -o StrictHostKeyChecking=no sshuser@$host 2>/dev/null || true
done

# Тест ansible (ping)
ansible all -m ping

# 3. Docker
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

# Загрузка образов из Additional.iso (если смонтирован)
ISO_MOUNT="/mnt/iso"
if [ -d "$ISO_MOUNT" ]; then
    if [ -f "$ISO_MOUNT/site_latest.tar" ]; then
        docker load < "$ISO_MOUNT/site_latest.tar"
    fi
    if [ -f "$ISO_MOUNT/mariadb_latest.tar" ]; then
        docker load < "$ISO_MOUNT/mariadb_latest.tar"
    fi
fi

# Docker-compose для testapp + mariadb
mkdir -p /opt/testapp
cat > /opt/testapp/docker-compose.yml <<'EOF'
version: '3'
services:
  mariadb:
    image: mariadb:latest
    container_name: testdb
    environment:
      MYSQL_ROOT_PASSWORD: P@sswOrd
      MYSQL_DATABASE: testdb
      MYSQL_USER: test
      MYSQL_PASSWORD: P@sswOrd
    ports:
      - "3306:3306"
    volumes:
      - db_data:/var/lib/mysql
    restart: unless-stopped

  testapp:
    image: testapp:latest
    container_name: testapp
    ports:
      - "8080:8080"
    depends_on:
      - mariadb
    environment:
      DB_HOST: mariadb
      DB_USER: test
      DB_PASSWORD: P@sswOrd
      DB_NAME: testdb
    restart: unless-stopped

volumes:
  db_data:
EOF

cd /opt/testapp && docker-compose up -d

echo "=== МОДУЛЬ 2: BR-SRV готова ==="