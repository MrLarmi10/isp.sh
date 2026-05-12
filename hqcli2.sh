#!/bin/bash
# Файл: hq-cli_setup.sh
# Настройка клиентской машины HQ-CLI: домен Samba, NFS, Яндекс Браузер

set -e

# IP-адрес
nmcli con mod eth0 ipv4.addresses 192.168.2.2/28 ipv4.method manual
nmcli con mod eth0 ipv4.gateway 192.168.2.1
nmcli con up eth0

# Установка пакетов для домена
dnf install -y samba-client samba-common oddjob oddjob-mkhomedir sssd realmd krb5-workstation

# Вход в домен au-team.irpo (пароль администратора домена предположительно P@ssword, но можно задать явно)
echo 'P@ssword' | realm join --user=Administrator au-team.irpo

# Настройка автоматического создания домашних каталогов
pam-auth-update --enable mkhomedir 2>/dev/null || true
systemctl enable --now sssd oddjobd

# Добавление sudo правил для группы sidehq
echo '%sidehq ALL=(ALL) NOPASSWD: /bin/cat, /bin/grep, /usr/bin/id' > /etc/sudoers.d/sidehq
chmod 440 /etc/sudoers.d/sidehq

# Автоматическое монтирование NFS
mkdir -p /mnt/nfs
echo '192.168.1.2:/raid1/nfs /mnt/nfs nfs defaults,_netdev 0 0' >> /etc/fstab
mount -a

# Установка Яндекс Браузера
dnf install -y wget
wget https://browser.yandex.ru/download/?os=linux -O yandex-browser.rpm
dnf install -y ./yandex-browser.rpm || true
# Если ссылка нерабочая, можно указать конкретную:
# wget https://repo.yandex.ru/yandex-browser/rpm/stable/x86_64/yandex-browser-stable-24.4.1.946-1.x86_64.rpm
# dnf install -y ./yandex-browser-stable-*.rpm