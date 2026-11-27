#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

source "$PROJECT_DIR/.env"

ASTERISK_VERSION="22"
ASTERISK_URL="https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}-current.tar.gz"
BUILD_DIR="$PROJECT_DIR/build"

trap 'echo "[ERROR] Instalace Asterisku selhala na řádku $LINENO." >&2' ERR

echo "========================================"
echo "          INSTALACE ASTERISKU"
echo "========================================"

# Kontrola oprávnění
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jsou vyžadována oprávnění root."
    exit 1
fi

if [[ "$PACKAGE_MANAGER" != "apt" || "$INIT_SYSTEM" != "systemd" ]]; then
    echo "[ERROR] Nepodporované systémové prostředí."
    exit 1
fi

echo "[INFO] Verze Asterisku: $ASTERISK_VERSION LTS"
echo "[INFO] Architektura: $ARCH"
echo "[INFO] CPU jádra: $CPU_CORES"

# Doplnění závislostí PJPROJECT
apt-get -o DPkg::Lock::Timeout=300 install -y python3-dev

# Příprava pracovního adresáře
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Stažení zdrojového kódu
echo "[INFO] Stahuji zdrojový kód Asterisku..."

wget -O asterisk.tar.gz "$ASTERISK_URL"

# Rozbalení archivu
echo "[INFO] Rozbaluji zdrojové soubory..."

mkdir -p source
tar -xzf asterisk.tar.gz \
    --strip-components=1 -C source

cd source

# Konfigurace kompilace
echo "[INFO] Konfiguruji Asterisk..."

./configure \
    --with-pjproject-bundled \
    --with-jansson-bundled

# Výběr modulů
echo "[INFO] Nastavuji požadované moduly..."

make menuselect.makeopts

menuselect/menuselect \
    --enable chan_pjsip \
    --enable res_pjsip \
    --enable pbx_config \
    --enable pbx_ael \
    --enable pbx_lua \
    --enable app_voicemail \
    --enable app_queue \
    --enable app_confbridge \
    --disable BUILD_NATIVE \
    menuselect.makeopts

# Omezení paralelní kompilace podle RAM
JOBS="$CPU_CORES"

if (( RAM_MB < 3000 )); then
    JOBS=2
fi

echo "[INFO] Kompilace Asterisku..."
echo "[INFO] Paralelní procesy: $JOBS"

make -j"$JOBS"

# Instalace
echo "[INFO] Instaluji Asterisk..."

make install

# Instalace výchozí konfigurace
if [[ ! -f /etc/asterisk/asterisk.conf ]]; then
    echo "[INFO] Instaluji výchozí konfiguraci..."
    make samples
fi

# Aktualizace knihoven
ldconfig

# Kontrola požadovaných modulů
echo "[INFO] Kontroluji moduly..."

for module in chan_pjsip res_pjsip pbx_config pbx_ael pbx_lua app_voicemail app_queue app_confbridge; do
    if [[ ! -f "$PWD"/"$module".so ]] &&
       ! find /usr/lib /usr/lib64 -path "*/asterisk/modules/$module.so" \
          -print -quit 2>/dev/null | grep -q .; then
        echo "[ERROR] Chybí modul: $module"
        exit 1
    fi

    echo "[OK] $module"
done

# Vytvoření systémového uživatele
if ! id asterisk >/dev/null 2>&1; then
    useradd --system --user-group \
        --home-dir /var/lib/asterisk \
        --shell /usr/sbin/nologin \
        asterisk
fi

# Nastavení adresářů a oprávnění
for dir in /var/lib/asterisk /var/log/asterisk \
           /var/spool/asterisk /var/cache/asterisk; do
    mkdir -p "$dir"
    chown -R asterisk:asterisk "$dir"
done

chown -R root:asterisk /etc/asterisk
chmod -R g+rX /etc/asterisk

# Vytvoření služby systemd
echo "[INFO] Vytvářím systémovou službu..."

ASTERISK_BIN="$(command -v asterisk)"

cat > /etc/systemd/system/asterisk.service <<EOF
[Unit]
Description=Asterisk VoIP PBX
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=asterisk
Group=asterisk
RuntimeDirectory=asterisk
ExecStart=$ASTERISK_BIN -f
ExecStop=$ASTERISK_BIN -rx "core stop gracefully"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Ověření instalace
echo "[INFO] Ověřuji instalaci..."

asterisk -V

echo "========================================"
echo "[OK] Instalace Asterisku dokončena."
echo "========================================"
