#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

source "$PROJECT_DIR/.env"

CONFIG_SOURCE="$PROJECT_DIR/config"
CONFIG_TARGET="/etc/asterisk"
BACKUP_DIR="/var/backups/asterisk/$(date +%Y%m%d_%H%M%S)"
TIMEZONE="Europe/Prague"

CONFIG_FILES=(
    pjsip.conf
    queues.conf
    voicemail.conf
    extensions.conf
    extensions.ael
    extensions.lua
)

trap 'echo "[ERROR] Konfigurace selhala na řádku $LINENO." >&2' ERR

echo "========================================"
echo "         KONFIGURACE ASTERISKU"
echo "========================================"

# Kontrola oprávnění
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jsou vyžadována oprávnění root."
    exit 1
fi

# Kontrola instalace Asterisku
if ! command -v asterisk >/dev/null 2>&1; then
    echo "[ERROR] Asterisk není nainstalován."
    exit 1
fi

# Kontrola konfiguračních souborů
echo "[INFO] Kontroluji konfigurační soubory..."

for file in "${CONFIG_FILES[@]}"; do

    if [[ ! -s "$CONFIG_SOURCE/$file" ]]; then
        echo "[ERROR] Soubor $file chybí nebo je prázdný."
        exit 1
    fi

    echo "[OK] $file"

done

# Nastavení časové zóny
echo "[INFO] Nastavuji časovou zónu..."

if [[ "$(timedatectl show -p Timezone --value)" != "$TIMEZONE" ]]; then
    timedatectl set-timezone "$TIMEZONE"
fi

echo "[OK] Časová zóna: $TIMEZONE"

# Zastavení služby
if systemctl is-active --quiet asterisk; then
    echo "[INFO] Zastavuji Asterisk..."
    systemctl stop asterisk
fi

# Záloha původní konfigurace
echo "[INFO] Zálohuji původní konfiguraci..."

umask 027

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

cp -a "$CONFIG_TARGET/." "$BACKUP_DIR/"

echo "[OK] Záloha: $BACKUP_DIR"

# Nasazení konfigurace
echo "[INFO] Nasazuji projektovou konfiguraci..."

for file in "${CONFIG_FILES[@]}"; do

    install \
        -o root \
        -g asterisk \
        -m 640 \
        "$CONFIG_SOURCE/$file" \
        "$CONFIG_TARGET/$file"

    echo "[OK] Nasazen $file"

done

# Konfigurace RTP
echo "[INFO] Nastavuji RTP..."

cat > "$CONFIG_TARGET/rtp.conf" <<'EOF'
[general]
rtpstart=10000
rtpend=20000
strictrtp=yes
EOF

# Konfigurace modulů
echo "[INFO] Nastavuji moduly Asterisku..."

cat > "$CONFIG_TARGET/modules.conf" <<'EOF'
[modules]
autoload=yes

require => pbx_config.so
require => pbx_ael.so
require => pbx_lua.so
require => chan_pjsip.so
require => res_pjsip.so
require => res_rtp_asterisk.so
require => app_queue.so
require => app_voicemail.so
require => res_musiconhold.so
require => func_db.so
require => func_callerid.so

noload => chan_iax2.so
noload => chan_dahdi.so
noload => chan_ooh323.so
noload => chan_mobile.so
noload => res_config_odbc.so
EOF

# Konfigurace logování
echo "[INFO] Nastavuji logování..."

cat > "$CONFIG_TARGET/logger.conf" <<'EOF'
[general]
dateformat=%F %T

[logfiles]
console => notice,warning,error,verbose
messages => notice,warning,error
full => notice,warning,error,debug,verbose
EOF

# Nastavení oprávnění
echo "[INFO] Nastavuji oprávnění..."

chown -R root:asterisk "$CONFIG_TARGET"

find "$CONFIG_TARGET" -type d -exec chmod 750 {} +
find "$CONFIG_TARGET" -type f -exec chmod 640 {} +

for dir in \
    /var/lib/asterisk \
    /var/log/asterisk \
    /var/spool/asterisk \
    /var/cache/asterisk; do

    mkdir -p "$dir"
    chown -R asterisk:asterisk "$dir"

done

# Načtení služby systemd
systemctl daemon-reload

# Spuštění služby
echo "[INFO] Spouštím Asterisk..."

systemctl enable asterisk

if ! systemctl start asterisk; then
    echo "[ERROR] Asterisk se nepodařilo spustit."
    journalctl -u asterisk -n 50 --no-pager
    exit 1
fi

# Čekání na dostupnost Asterisk CLI
echo "[INFO] Čekám na inicializaci ústředny..."

READY=0

for ((i=1; i<=30; i++)); do

    if asterisk -rx "core show uptime" >/dev/null 2>&1; then
        READY=1
        break
    fi

    sleep 1

done

if [[ "$READY" -ne 1 ]]; then
    echo "[ERROR] Asterisk CLI není dostupné."
    journalctl -u asterisk -n 50 --no-pager
    exit 1
fi

# Nastavení výchozího provozního režimu
asterisk -rx "database put voip mode auto"

# Nastavení diagnostických výpisů
asterisk -rx "core set verbose 5"

# Kontrola služby
if ! systemctl is-active --quiet asterisk; then
    echo "[ERROR] Služba Asterisk neběží."
    exit 1
fi

echo "[OK] Asterisk je spuštěn."

# Zobrazení informací
asterisk -rx "core show version"
asterisk -rx "core show uptime"

echo "========================================"
echo "[OK] Konfigurace Asterisku dokončena."
echo "========================================"
