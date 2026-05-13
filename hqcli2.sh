#!/bin/bash
# hq-cli_setup.sh — исправленный, с проверкой сети

SUDO_PASS="P@ssword"

run_sudo() {
    echo "$SUDO_PASS" | sudo -S bash -c "$1"
}

# === 1. Установка пакетов ===
echo "=== 1. Установка пакетов ==="
run_sudo "dnf install -y samba-client samba-common oddjob oddjob-mkhomedir sssd realmd krb5-workstation adcli"

# === 2. Настройка DNS ===
echo "=== 2. Настройка DNS ==="
run_sudo "systemctl stop systemd-resolved 2>/dev/null || true"
run_sudo "systemctl mask systemd-resolved 2>/dev/null || true"
run_sudo "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
run_sudo "echo 'nameserver 192.168.4.2' >> /etc/resolv.conf"
run_sudo "echo 'search au-team.irpo' >> /etc/resolv.conf"

# === 3. Проверка Интернета ===
if ! run_sudo "ping -c 2 google.com &>/dev/null"; then
    echo "ВНИМАНИЕ: Нет интернета. Установка браузера будет пропущена."
fi

# === 4. Вход в домен ===
echo "=== 4. Вход в домен ==="
echo "$SUDO_PASS" | sudo -S realm join --user=Administrator au-team.irpo

# === 5. Автосоздание домашних каталогов ===
run_sudo "grep -q 'pam_mkhomedir.so' /etc/pam.d/common-session || echo 'session optional pam_mkhomedir.so skel=/etc/skel umask=077' >> /etc/pam.d/common-session"
run_sudo "systemctl enable --now sssd oddjobd"

# === 6. Sudo для группы sidehq ===
run_sudo "echo '%sidehq ALL=(ALL) NOPASSWD: /bin/cat, /bin/grep, /usr/bin/id' > /etc/sudoers.d/sidehq"
run_sudo "chmod 440 /etc/sudoers.d/sidehq"

# === 7. Монтирование NFS (с проверкой) ===
echo "=== 7. Монтирование NFS ==="
run_sudo "mkdir -p /mnt/nfs"
if run_sudo "ping -c 2 192.168.1.2 &>/dev/null"; then
    run_sudo "echo '192.168.1.2:/raid1/nfs /mnt/nfs nfs defaults,_netdev 0 0' >> /etc/fstab"
    run_sudo "systemctl daemon-reload"
    run_sudo "mount -a"
else
    echo "NFS-сервер 192.168.1.2 недоступен. Монтирование пропущено."
fi

# === 8. Установка Яндекс Браузера ===
echo "=== 8. Установка Яндекс Браузера ==="
if run_sudo "ping -c 2 google.com &>/dev/null"; then
    run_sudo "dnf install -y yandex-browser-stable"
else
    echo "Нет интернета — браузер не установлен."
fi

echo "=== Настройка HQ-CLI завершена ==="