#!/bin/bash
# br-srv_setup.sh — исправленная версия

set -e

# Изменение порта SSH на 2026
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

# 1. Установка Samba DC
dnf install -y samba samba-client samba-dc bind bind-utils

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

# 2. Создание пользователей и группы (исправлено)
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

# 3. Ansible
dnf install -y ansible
mkdir -p /etc/ansible
cat > /etc/ansible/hosts <<EOF
[servers]
HQ-SRV ansible_host=192.168.1.2 ansible_user=root ansible_ssh_pass=P@ssword ansible_ssh_port=2026
HQ-CLI ansible_host=192.168.2.2 ansible_user=User ansible_ssh_pass=P@ssword
HQ-RTR ansible_host=172.16.1.2 ansible_user=root ansible_ssh_pass=P@ssword
BR-RTR ansible_host=172.16.2.2 ansible_user=root ansible_ssh_pass=P@ssword
EOF
ansible all -m ping -i /etc/ansible/hosts || true

# 4. Docker
dnf install -y docker docker-compose
systemctl enable --now docker

# Монтирование ISO (если есть)
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
    docker load -i "$ISO_MOUNT/docker/site_latest.tar" || true
    docker load -i "$ISO_MOUNT/docker/postgresql_latest.tar" || true
else
    echo "Предупреждение: образы Docker не найдены."
fi

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

echo "BR-SRV настроен."