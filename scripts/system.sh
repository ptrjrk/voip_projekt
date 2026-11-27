#!/usr/bin/env bash

set -Eeuo pipefail

echo "[INFO] Probíhá detekce systému..."

# Kontrola operačního systému
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "[ERROR] Operační systém není Linux."
    exit 1
fi

# Detekce distribuce
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
else
    echo "[ERROR] Nelze identifikovat distribuci."
    exit 1
fi

OS_ID="${ID:-unknown}"
OS_NAME="${PRETTY_NAME:-unknown}"
OS_VERSION="${VERSION_ID:-unknown}"
ARCH="$(uname -m)"
CPU_CORES="$(nproc)"
RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
DISK_MB="$(df -Pm / | awk 'NR==2 {print $4}')"

# Detekce správce balíčků
if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"
elif command -v yum >/dev/null 2>&1; then
    PACKAGE_MANAGER="yum"
elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"
elif command -v zypper >/dev/null 2>&1; then
    PACKAGE_MANAGER="zypper"
elif command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"
else
    echo "[ERROR] Nepodporovaný správce balíčků."
    exit 1
fi

# Detekce správce služeb
if [[ -d /run/systemd/system ]]; then
    INIT_SYSTEM="systemd"
elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
else
    INIT_SYSTEM="unknown"
fi

# Kontrola DNS
if getent hosts github.com >/dev/null 2>&1; then
    NETWORK="DNS OK"
else
    NETWORK="DNS ERROR"
    echo "[WARN] Nelze přeložit adresu github.com."
fi

# Výpis informací
echo "========================================"
echo "         INFORMACE O SYSTÉMU"
echo "========================================"
echo "Distribuce:       $OS_NAME"
echo "ID distribuce:    $OS_ID"
echo "Verze:            $OS_VERSION"
echo "Architektura:     $ARCH"
echo "CPU jádra:        $CPU_CORES"
echo "RAM:              $RAM_MB MB"
echo "Volný disk:       $DISK_MB MB"
echo "Správce balíčků:  $PACKAGE_MANAGER"
echo "Správce služeb:   $INIT_SYSTEM"
echo "Síť:              $NETWORK"
echo "========================================"

# Uložení proměnných pro další skripty
{
    printf 'OS_ID=%q\n' "$OS_ID"
    printf 'OS_NAME=%q\n' "$OS_NAME"
    printf 'OS_VERSION=%q\n' "$OS_VERSION"
    printf 'ARCH=%q\n' "$ARCH"
    printf 'CPU_CORES=%q\n' "$CPU_CORES"
    printf 'RAM_MB=%q\n' "$RAM_MB"
    printf 'DISK_MB=%q\n' "$DISK_MB"
    printf 'PACKAGE_MANAGER=%q\n' "$PACKAGE_MANAGER"
    printf 'INIT_SYSTEM=%q\n' "$INIT_SYSTEM"
} > "$PROJECT_DIR/.env"

echo "[OK] Detekce systému dokončena."
