
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

source "$PROJECT_DIR/.env"

ASTERISK_VERSION="22"
ASTERISK_URL="https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}-current.tar.gz"
BUILD_DIR="$PROJECT_DIR/build"

REQUIRED_MODULES=(
    chan_pjsip
    res_pjsip
    res_rtp_asterisk
    pbx_config
    pbx_ael
    pbx_lua
    app_dial
    app_voicemail
    app_queue
    app_confbridge
    app_playback
    app_read
    app_echo
    codec_alaw
    codec_ulaw
    codec_g722
)

trap 'echo "[ERROR] Instalace Asterisku selhala na řádku $LINENO." >&2' ERR

echo "========================================"
echo "     ASTERISK - MINIMAL INSTALLATION"
echo "========================================"

# Kontrola oprávnění
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jsou vyžadována oprávnění root."
    exit 1
fi

# Kontrola systémového prostředí
if [[ "$PACKAGE_MANAGER" != "apt" || "$INIT_SYSTEM" != "systemd" ]]; then
    echo "[ERROR] Nepodporované systémové prostředí."
    exit 1
fi

echo "[INFO] Verze: Asterisk $ASTERISK_VERSION LTS"
echo "[INFO] Architektura: $ARCH"
echo "[INFO] CPU jádra: $CPU_CORES"
echo "[INFO] RAM: $RAM_MB MB"

# Příprava pracovního adresáře
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Stažení zdrojového kódu
echo "[INFO] Stahuji zdrojový kód Asterisku..."

wget -q --show-progress \
    -O asterisk.tar.gz "$ASTERISK_URL"

# Rozbalení archivu
echo "[INFO] Rozbaluji zdrojový kód..."

SOURCE_DIR="$(mktemp -d "$BUILD_DIR/source.XXXXXX")"

tar -xzf asterisk.tar.gz \
    --strip-components=1 \
    -C "$SOURCE_DIR"

cd "$SOURCE_DIR"

# Konfigurace kompilace
echo "[INFO] Konfiguruji Asterisk..."

./configure \
    --with-pjproject-bundled \
    --without-jansson-bundled

# Příprava Menuselect
echo "[INFO] Připravuji výběr modulů..."

make menuselect.makeopts

# Omezení nepotřebných modulů
echo "[INFO] Vypínám nepotřebné komponenty..."

menuselect/menuselect \
    --disable-category MENUSELECT_CHANNELS \
    --disable-category MENUSELECT_TESTS \
    --disable-category MENUSELECT_ADDONS \
    --disable BUILD_NATIVE \
    menuselect.makeopts

# Povolení požadovaných modulů
echo "[INFO] Povoluji požadované moduly..."

for module in "${REQUIRED_MODULES[@]}"; do
    menuselect/menuselect \
        --enable "$module" \
        menuselect.makeopts

    echo "[SELECT] $module"
done

# Kontrola závislostí modulů
menuselect/menuselect \
    --check-deps menuselect.makeopts

# Nastavení paralelní kompilace
JOBS="$CPU_CORES"

if (( RAM_MB < 3000 )); then
    JOBS=2
fi

echo "[INFO] Paralelní procesy: $JOBS"

# Kompilace
echo "[INFO] Probíhá kompilace Asterisku..."

make -j"$JOBS"

echo "[OK] Kompilace dokončena."

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

# Kontrola nainstalovaných modulů
echo "[INFO] Ověřuji požadované moduly..."

for module in "${REQUIRED_MODULES[@]}"; do

    MODULE_FILE="$(find /usr/lib /usr/local/lib \
        -path "*/asterisk/modules/$module.so" \
        -print -quit 2>/dev/null || true)"

    if [[ -z "$MODULE_FILE" ]]; then
        echo "[ERROR] Chybí modul: $module"
        exit 1
    fi

    echo "[OK] $module"
done

# Vytvoření systémového uživatele
if ! id asterisk >/dev/null 2>&1; then
    echo "[INFO] Vytvářím uživatele asterisk..."

    useradd --system --user-group \
        --home-dir /var/lib/asterisk \
        --shell /usr/sbin/nologin \
        asterisk
else
    echo "[SKIP] Uživatel asterisk již existuje."
fi

# Vytvoření potřebných adresářů
echo "[INFO] Nastavuji adresáře a oprávnění..."

for dir in \
    /var/lib/asterisk \
    /var/log/asterisk \
    /var/spool/asterisk \
    /var/cache/asterisk; do

    mkdir -p "$dir"
    chown -R asterisk:asterisk "$dir"
done

chown -R root:asterisk /etc/asterisk
chmod -R g+rX /etc/asterisk

# Vytvoření služby systemd
echo "[INFO] Vytvářím službu systemd..."

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
echo "[INFO] Ověřuji verzi Asterisku..."

asterisk -V

echo "========================================"
echo "[OK] Instalace Asterisku dokončena."
echo "========================================"
