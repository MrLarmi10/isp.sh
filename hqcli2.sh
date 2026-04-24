#!/bin/bash

# =====================================================
# МОДУЛЬ 2: Настройка HQ-CLI
# - Ввод в домен au-team.irpo (Samba DC на BR-SRV)
# - Монтирование NFS (/mnt/nfs)
# - Установка Яндекс Браузера
# =====================================================

set -e

echo "=== МОДУЛЬ 2: Настройка HQ-CLI ==="

# 1. Ввод в домен au-team.irpo
dnf install -y samba-client samba-common realmd oddjob oddjob-mkhomedir adcli sssd

# Настройка DNS на HQ-SRV
nmcli con mod eth0 ipv4.dns "192.168.10.2"
nmcli con up eth0

# Обнаружение домена
realm discover au-team.irpo

# Ввод в домен (требует пароль администратора)
echo "P@sswOrd" | realm join --user=administrator au-team.irpo

# Настройка автоматического создания домашней директории
pam-config --add --mkhomedir

# Разрешение пользователям группы hq аутентифицироваться
cat > /etc/sssd/sssd.conf.d/au-team.irpo.conf <<'EOF'
[domain/au-team.irpo]
simple_allow_groups = hq
EOF

systemctl restart sssd

# 2. Монтирование NFS с HQ-SRV
dnf install -y nfs-utils

mkdir -p /mnt/nfs

# Добавление в fstab для автоматического монтирования
echo "192.168.10.2:/raid/nfs /mnt/nfs nfs defaults 0 0" >> /etc/fstab

# Монтирование
mount /mnt/nfs

# 3. Установка Яндекс Браузера
cat > /etc/yum.repos.d/yandex-browser.repo <<'EOF'
[yandex-browser]
name=Yandex Browser
baseurl=https://repo.yandex.ru/yandex-browser/rpm/stable/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://repo.yandex.ru/yandex-browser/YANDEX-BROWSER-KEY.GPG
EOF

dnf install -y yandex-browser-stable

echo "=== МОДУЛЬ 2: HQ-CLI готова ==="