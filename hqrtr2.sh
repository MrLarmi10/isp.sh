#!/bin/bash

# =====================================================
# МОДУЛЬ 2: Настройка HQ-RTR
# - Статическая трансляция портов
# - 8080 -> HQ-SRV:80 (веб приложение)
# - 2026 -> HQ-SRV:3026 (SSH на порт 2026)
# =====================================================

set -e

echo "=== МОДУЛЬ 2: Настройка HQ-RTR ==="

# 1. Добавление правил DNAT (статическая трансляция портов)
nft add rule ip nat prerouting tcp dport 8080 dnat to 192.168.10.2:80
nft add rule ip nat prerouting tcp dport 2026 dnat to 192.168.10.2:3026

# 2. Сохранение правил nftables
nft list ruleset > /etc/nftables/hq-nat.nft

echo "=== МОДУЛЬ 2: HQ-RTR готова ==="