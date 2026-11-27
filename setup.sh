#!/bin/bash

set -euo pipefail

REPO_URL="https://github.com/ptrjrk/voip_projekt.git"
PROJECT_DIR=$(mktemp -d /tmp/voip_projekt.XXXXXX)

echo "========================================"
echo "       VoIP I - Project Setup"
echo "========================================"

echo "[INFO] Stahuji repozitář..."

git clone --depth 1 --branch main \
    "$REPO_URL" "$PROJECT_DIR"

cd "$PROJECT_DIR"

echo "[INFO] Spouštím instalaci..."

sudo bash install.sh

echo "[OK] Instalace dokončena."
