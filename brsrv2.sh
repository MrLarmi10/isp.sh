#!/bin/bash
# Файл: br-srv_setup.sh
# Настройка контроллера домена Samba DC, ansible, docker-приложения

set -e

# IP-адрес
nmcli con mod eth0 ipv4.addresses 192.168.4.2/28 ipv4.method manual
nmcli con mod eth0 ipv4.gateway 192.168.4.1
nmcli con up eth0

# Изменение порта SSH на 2026
sed -i 's/^#Port 22/Port 2026/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 2026/' /etc/ssh/sshd_config
systemctl restart sshd

# --- Samba DC ---
dnf install -y samba samba-client samba-dc bind bind-utils
# Настройка домена (автоматизированный ответ)
rm -f /etc/samba/smb.conf
samba-tool domain provision --use-rfc2307 --realm=AU-TEAM.IRPO --domain=AU-TEAM --adminpass='P@ssword' --server-role=dc --dns-backend=SAMBA_INTERNAL
mv /etc/samba/smb.conf /etc/samba/smb.conf.back
samba-tool domain provision --use-rfc2307 --realm=AU-TEAM.IRPO --domain=AU-TEAM --adminpass='P@ssword' --server-role=dc --dns-backend=SAMBA_INTERNAL --option="interfaces=lo eth0" --option="bind interfaces only=yes"
systemctl mask systemd-resolved
systemctl stop systemd-resolved
systemctl enable samba --now
# Прописать DC в resolv.conf
echo "nameserver 192.168.4.2" > /etc/resolv.conf
echo "search au-team.irpo" >> /etc/resolv.conf

# Создание пользователей и группы
for i in 1 2 3 4 5; do
    samba-tool user create sidehquser$i --given-name=Side --surname=HQUser$i --must-change-at-next-login=false --password='P@ssword'
done
samba-tool group add sidehq
for i in 1 2 3 4 5; do
    samba-tool group addmembers sidehq sidehquser$i
done

# Добавление компьютера HQ-CLI в домен (по желанию, клиент сам присоединится)
samba-tool computer add HQ-CLI --password='P@ssword'

# --- Ansible ---
dnf install -y ansible
mkdir -p /etc/ansible
cat > /etc/ansible/hosts <<EOF
[servers]
HQ-SRV ansible_host=192.168.1.2 ansible_user=root ansible_ssh_pass=P@ssword ansible_ssh_port=2026
HQ-CLI ansible_host=192.168.2.2 ansible_user=root ansible_ssh_pass=P@ssword
HQ-RTR ansible_host=172.16.1.2 ansible_user=root ansible_ssh_pass=P@ssword
BR-RTR ansible_host=172.16.2.2 ansible_user=root ansible_ssh_pass=P@ssword
EOF
# Проверка ping (должна выполняться без ошибок)
ansible all -m ping -i /etc/ansible/hosts

# --- Docker и приложение ---
dnf install -y docker docker-compose
systemctl enable --now docker
# Импорт образов из Additional.iso (предполагается, что ISO смонтирован в /mnt/iso)
mount /dev/cdrom /mnt/iso || true
docker load -i /mnt/iso/docker/site_latest.tar
docker load -i /mnt/iso/docker/postgresql_latest.tar
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