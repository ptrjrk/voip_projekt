#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

echo "[1/5] Příprava systému..."
bash scripts/system.sh

echo "[2/5] Instalace závislostí..."
bash scripts/dependencies.sh

echo "[3/5] Instalace Asterisku..."
bash scripts/asterisk.sh

echo "[4/5] Konfigurace Asterisku..."
bash scripts/configuration.sh

echo "[5/5] Ověření funkčnosti..."
bash scripts/verification.sh

echo "[OK] Projekt je připraven k použití."
