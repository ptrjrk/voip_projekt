
#!/usr/bin/env bash

set -Eeuo pipefail

REPO_URL="https://github.com/ptrjrk/voip_projekt.git"
INSTALL_DIR="/opt/voip_projekt"

# Automatické získání oprávnění
if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

echo "[INFO] Spouštím automatickou instalaci..."

# Instalace Gitu
if ! command -v git >/dev/null 2>&1; then

    echo "[INFO] Instaluji Git..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y git ca-certificates

    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y git ca-certificates

    elif command -v yum >/dev/null 2>&1; then
        yum install -y git ca-certificates

    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --needed --noconfirm git ca-certificates

    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install git ca-certificates

    elif command -v apk >/dev/null 2>&1; then
        apk add git ca-certificates

    else
        echo "[ERROR] Nepodporovaná distribuce."
        exit 1
    fi
fi

# Stažení nebo aktualizace projektu
if [[ -d "$INSTALL_DIR/.git" ]]; then

    echo "[INFO] Aktualizuji repozitář..."
    git -C "$INSTALL_DIR" pull --ff-only

else

    echo "[INFO] Stahuji repozitář..."
    git clone "$REPO_URL" "$INSTALL_DIR"

fi

# Spuštění instalace
cd "$INSTALL_DIR"

echo "[INFO] Spouštím install.sh..."

bash install.sh

echo "[OK] Instalační proces dokončen."
