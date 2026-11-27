#!/usr/bin/env bash

set -Eeuo pipefail

# Kontrola oprávnění
if [[ $EUID -ne 0 ]]; then
    echo "Spusť instalační skript jako root nebo pomocí sudo."
    exit 1
fi

# Adresáře projektu
export PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTS_DIR="$PROJECT_DIR/scripts"
export CONFIG_DIR="$PROJECT_DIR/config"
export EVIDENCE_DIR="$PROJECT_DIR/evidence"

mkdir -p "$EVIDENCE_DIR"

# Instalační fáze
STAGES=(
    "system.sh"
    "dependencies.sh"
    "asterisk.sh"
    "configuration.sh"
    "verification.sh"
    "capture.sh"
)

echo "========================================"
echo "       VoIP Projekt - instalace"
echo "========================================"

for STAGE in "${STAGES[@]}"; do
    echo ""
    echo "[INFO] Spouštím $STAGE"

    if [[ ! -f "$SCRIPTS_DIR/$STAGE" ]]; then
        echo "[ERROR] Skript $STAGE neexistuje."
        exit 1
    fi

    bash "$SCRIPTS_DIR/$STAGE"

    echo "[OK] $STAGE dokončen."
done

echo ""
echo "========================================"
echo "       Všechny skripty dokončeny"
echo "========================================"
