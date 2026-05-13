#!/bin/bash
# hq-cli_setup.sh — исправленный

set -e

SUDO_PASS="P@ssword"

run_sudo() {
    echo "$SUDO_PASS" | sudo -S bash -c "$1"
}

# Установка пакетов
run_sudo "dnf install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli samba-common"

# Отключаем systemd-resolved, если активен
run_sudo "systemctl stop systemd-resolved 2>/dev/null || true"
run_sudo "systemctl mask systemd-resolved 2>/dev/null || true"

# Настраиваем DNS на контроллер домена
run_sudo "echo 'nameserver 192.168.4.2' > /etc/resolv.conf"
run_sudo "echo 'search au-team.irpo' >> /etc/resolv.conf"
# Защищаем resolv.conf от перезаписи
run_sudo "chattr +i /etc/resolv.conf"

# Проверяем доступность домена
run_sudo "ping -c 1 au-team.irpo" || echo "Предупреждение: домен не пингуется"

# Вход в домен (пароль администратора P@ssword)
echo 'P@ssword' | run_sudo "realm join --user=Administrator au-team.irpo" || {
    echo "Ошибка входа в домен, пробуем через adcli"
    echo 'P@ssword' | run_sudo "adcli join au-team.irpo --user=Administrator"
}

# Настройка автодомашних каталогов
run_sudo "pam-auth-update --enable mkhomedir" 2>/dev/null || run_sudo "echo 'session optional pam_mkhomedir.so skel=/etc/skel umask=077' >> /etc/pam.d/common-session"
run_sudo "systemctl enable --now sssd oddjobd"

# Sudo для sidehq
run_sudo "echo '%sidehq ALL=(ALL) NOPASSWD: /bin/cat, /bin/grep, /usr/bin/id' > /etc/sudoers.d/sidehq"
run_sudo "chmod 440 /etc/sudoers.d/sidehq"

# NFS
run_sudo "mkdir -p /mnt/nfs"
run_sudo "echo '192.168.1.2:/raid1/nfs /mnt/nfs nfs defaults,_netdev 0 0' >> /etc/fstab"
run_sudo "mount -a"

# Яндекс Браузер
cd /tmp
wget https://browser.yandex.ru/download/?os=linux -O yandex-browser.rpm
run_sudo "dnf install -y /tmp/yandex-browser.rpm" || echo "Яндекс Браузер не установлен"
rm -f yandex-browser.rpm

echo "Настройка HQ-CLI завершена"