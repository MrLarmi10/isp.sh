#!/bin/bash
# hq-cli_setup.sh - без настройки IP

set -e

# Установка пакетов для домена
dnf install -y samba-client samba-common oddjob oddjob-mkhomedir sssd realmd krb5-workstation

# Вход в домен au-team.irpo
echo 'P@ssword' | realm join --user=Administrator au-team.irpo

# Автоматическое создание домашних каталогов
if command -v pam-auth-update &>/dev/null; then
    pam-auth-update --enable mkhomedir
else
    # ручная настройка для RedOS
    echo "session optional pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session
fi
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