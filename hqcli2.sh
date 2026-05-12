#!/bin/bash
# hq-cli_setup.sh (запускать от обычного пользователя User)

set -e

SUDO_PASS="P@ssword"

run_sudo() {
    echo "$SUDO_PASS" | sudo -S bash -c "$1"
}

# Установка пакетов для домена
run_sudo "dnf install -y samba-client samba-common oddjob oddjob-mkhomedir sssd realmd krb5-workstation"

# Вход в домен au-team.irpo (администратор домена, пароль P@ssword)
echo "$SUDO_PASS" | sudo -S realm join --user=Administrator au-team.irpo <<< "$SUDO_PASS"

# Включение автозоздания домашних каталогов
if ! run_sudo "grep -q pam_mkhomedir.so /etc/pam.d/common-session"; then
    run_sudo "echo 'session optional pam_mkhomedir.so skel=/etc/skel umask=077' >> /etc/pam.d/common-session"
fi
run_sudo "systemctl enable --now sssd oddjobd"

# Sudo для группы sidehq (только cat, grep, id)
run_sudo "echo '%sidehq ALL=(ALL) NOPASSWD: /bin/cat, /bin/grep, /usr/bin/id' > /etc/sudoers.d/sidehq"
run_sudo "chmod 440 /etc/sudoers.d/sidehq"

# Монтирование NFS
run_sudo "mkdir -p /mnt/nfs"
if ! run_sudo "grep -q '192.168.1.2:/raid1/nfs' /etc/fstab"; then
    run_sudo "echo '192.168.1.2:/raid1/nfs /mnt/nfs nfs defaults,_netdev 0 0' >> /etc/fstab"
fi
run_sudo "mount -a"

# Установка Яндекс Браузера (загрузка в /tmp)
cd /tmp
wget https://browser.yandex.ru/download/?os=linux -O yandex-browser.rpm
run_sudo "dnf install -y /tmp/yandex-browser.rpm" || echo "Не удалось установить Яндекс Браузер"
rm -f yandex-browser.rpm

echo "Настройка HQ-CLI завершена."