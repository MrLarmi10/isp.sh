#!/bin/bash

# =====================================================
# МОДУЛЬ 2: Настройка BR-RTR
# - Статическая трансляция портов
# - 8080 -> BR-SRV:8080 (testapp)
# - 2026 -> BR-SRV:3026 (SSH на порт 2026)
# =====================================================

set -e

echo "=== МОДУЛЬ 2: Настройка BR-RTR ==="

# 1. Добавление правил DNAT
nft add rule ip nat prerouting tcp dport 8080 dnat to 192.168.200.2:8080
nft add rule ip nat prerouting tcp dport 2026 dnat to 192.168.200.2:3026

# 2. Сохранение правил
nft list ruleset > /etc/nftables/br-nat.nft

echo "=== МОДУЛЬ 2: BR-RTR готова ==="