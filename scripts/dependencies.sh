#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Kontrola oprávnění
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Skript vyžaduje oprávnění root."
    exit 1
fi

# Načtení systémových informací
if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    echo "[ERROR] Soubor .env nebyl nalezen."
    exit 1
fi

source "$PROJECT_DIR/.env"

trap 'echo "[ERROR] Instalace závislostí selhala na řádku $LINENO." >&2' ERR

echo "========================================"
echo "         INSTALACE ZÁVISLOSTÍ"
echo "========================================"

echo "[INFO] Distribuce: $OS_NAME"
echo "[INFO] Architektura: $ARCH"
echo "[INFO] Správce balíčků: $PACKAGE_MANAGER"

case "$PACKAGE_MANAGER" in

    apt)
        export DEBIAN_FRONTEND=noninteractive

        PACKAGES=(
            build-essential
            gcc
            g++
            make
            cmake
            autoconf
            automake
            libtool
            pkg-config
            git
            wget
            curl
            ca-certificates
            tar
            gzip
            bzip2
            xz-utils
            patch
            bison
            flex
            libssl-dev
            libncurses-dev
            libxml2-dev
            libsqlite3-dev
            libjansson-dev
            uuid-dev
            libedit-dev
            libcurl4-openssl-dev
            libspeex-dev
            libspeexdsp-dev
            libopus-dev
            libsrtp2-dev
            liblua5.4-dev
            libnewt-dev
            liburiparser-dev
            libiksemel-dev
            unixodbc-dev
            zlib1g-dev
            libpopt-dev
            libogg-dev
            libvorbis-dev
            libasound2-dev
            libspandsp-dev
            libsndfile1-dev
            python3
            perl
            sox
            ffmpeg
            sngrep
            tcpdump
            tshark
            iproute2
            iputils-ping
            dnsutils
        )

        echo "[INFO] Aktualizuji seznam balíčků..."

        apt-get \
            -o Acquire::Retries=3 \
            -o APT::Update::Error-Mode=any \
            update

        echo "[INFO] Instaluji závislosti..."

        # Neumožníme, aby jediný volitelný nedostupný
        # balíček zablokoval celou instalaci.
        AVAILABLE_PACKAGES=()

        for package in "${PACKAGES[@]}"; do
            if apt-cache show "$package" >/dev/null 2>&1; then
                AVAILABLE_PACKAGES+=("$package")
            else
                echo "[WARN] Nedostupný balíček: $package"
            fi
        done

        apt-get \
            -o DPkg::Lock::Timeout=300 \
            install -y "${AVAILABLE_PACKAGES[@]}"
        ;;

    *)
        echo "[ERROR] Správce $PACKAGE_MANAGER zatím není implementován."
        exit 1
        ;;

esac

# Kontrola základních nástrojů
echo "[INFO] Ověřuji nainstalované nástroje..."

REQUIRED_TOOLS=(
    gcc
    g++
    make
    git
    wget
    curl
    pkg-config
)

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "[OK] $tool"
    else
        echo "[ERROR] Chybí nástroj: $tool"
        exit 1
    fi
done

echo "========================================"
echo "[OK] Instalace závislostí dokončena."
echo "========================================"
