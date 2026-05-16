#!/bin/bash
# hq-cli_setup.sh — исправленный (без chattr, с проверкой DNS)

set -e

# === 1. Установка Яндекс Браузера ===
echo "=== 1. Установка Яндекс Браузера ==="
    run_sudo "dnf install -y yandex-browser-stable"
else
    echo "Нет интернета — браузер не установлен."
fi

SUDO_PASS="P@ssword"

run_sudo() {
    echo "$SUDO_PASS" | sudo -S bash -c "$1"
}

echo "=== 2. Установка пакетов ==="
run_sudo "dnf install -y samba-client samba-common oddjob oddjob-mkhomedir sssd realmd krb5-workstation adcli"



echo "=== 3. Настройка DNS (контроллер домена) ==="
run_sudo "systemctl stop systemd-resolved 2>/dev/null || true"
run_sudo "systemctl mask systemd-resolved 2>/dev/null || true"
run_sudo "echo 'nameserver 192.168.4.2' > /etc/resolv.conf"
run_sudo "echo 'search au-team.irpo' >> /etc/resolv.conf"

echo "=== 4. Проверка разрешения домена ==="
if ! run_sudo "nslookup au-team.irpo 192.168.4.2" | grep -q "192.168.4.2"; then
    echo "ОШИБКА: не удаётся разрешить домен au-team.irpo. Проверьте DNS на BR-SRV (192.168.4.2)."
    exit 1
fi

echo "=== 5. Вход в домен ==="
# Установка DNS и домена поиска через nmcli
nmcli con mod ens160.200 ipv4.dns "192.168.4.2"
nmcli con mod ens160.200 ipv4.dns-search "au-team.irpo"
nmcli con up ens160.200

echo "$SUDO_PASS" | sudo -S realm join --user=Administrator au-team.irpo || {
    echo "ОШИБКА: не удалось войти в домен. Проверьте работу Samba DC."
    exit 1
}

echo "=== 6. Автосоздание домашних каталогов ==="
run_sudo "grep -q 'pam_mkhomedir.so' /etc/pam.d/common-session || echo 'session optional pam_mkhomedir.so skel=/etc/skel umask=077' >> /etc/pam.d/common-session"
run_sudo "systemctl enable --now sssd oddjobd"

echo "=== 7. Sudo для группы sidehq ==="
run_sudo "echo '%sidehq ALL=(ALL) NOPASSWD: /bin/cat, /bin/grep, /usr/bin/id' > /etc/sudoers.d/sidehq"
run_sudo "chmod 440 /etc/sudoers.d/sidehq"

# === 8. Монтирование NFS (с проверкой) ===
echo "=== 8. Монтирование NFS ==="
run_sudo "mkdir -p /mnt/nfs"
if run_sudo "ping -c 2 192.168.1.2 &>/dev/null"; then
    run_sudo "echo '192.168.1.2:/raid1/nfs /mnt/nfs nfs defaults,_netdev 0 0' >> /etc/fstab"
    run_sudo "systemctl daemon-reload"
    run_sudo "mount -a"
else
    echo "NFS-сервер 192.168.1.2 недоступен. Монтирование пропущено."
fi



echo "=== Настройка HQ-CLI завершена ==="







