#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jsou vyžadována oprávnění root."
    exit 1
fi

source "$PROJECT_DIR/.env"

trap 'echo "[ERROR] Instalace závislostí selhala na řádku $LINENO." >&2' ERR

echo "========================================"
echo "       INSTALACE ZÁVISLOSTÍ"
echo "========================================"

case "$PACKAGE_MANAGER" in
    apt)
        export DEBIAN_FRONTEND=noninteractive

        PACKAGES=(
            build-essential
            pkg-config
            git
            wget
            curl
            ca-certificates
            tar
            gzip
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
            libsrtp2-dev
            liblua5.4-dev
            zlib1g-dev
            python3
            python3-dev
            perl
            sox
            sngrep
            tcpdump
            tshark
            iproute2
        )

        echo "[INFO] Aktualizuji seznam balíčků..."

        apt-get \
            -o Acquire::Retries=3 \
            -o APT::Update::Error-Mode=any \
            update

        echo "[INFO] Kontroluji potřebné balíčky..."

        MISSING_PACKAGES=()

        for package in "${PACKAGES[@]}"; do
            if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" == "install ok installed" ]]; then
                echo "[SKIP] $package je již nainstalován."
            else
                echo "[NEED] $package"
                MISSING_PACKAGES+=("$package")
            fi
        done

        if (( ${#MISSING_PACKAGES[@]} > 0 )); then
            echo "[INFO] Instaluji pouze chybějící balíčky..."

            apt-get \
                -o DPkg::Lock::Timeout=300 \
                install -y --no-install-recommends \
                "${MISSING_PACKAGES[@]}"
        else
            echo "[OK] Všechny potřebné balíčky jsou již nainstalovány."
        fi
        ;;

    *)
        echo "[ERROR] Nepodporovaný správce balíčků: $PACKAGE_MANAGER"
        exit 1
        ;;
esac

echo "========================================"
echo "[OK] Instalace závislostí dokončena."
echo "========================================"
