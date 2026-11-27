
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

SCENARIO="${1:-}"
IMPLEMENTATION="${2:-}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-/data/voip_evidence}"

CAPTURE_PID=""
LOG_PID=""

umask 077

# Kontrola oprávnění

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jsou vyžadována oprávnění root."
    exit 1
fi

# Kontrola argumentů

if [[ ! "$SCENARIO" =~ ^T[0-9]{2}$ ]]; then
    echo "[ERROR] Neplatné ID testovacího scénáře."
    echo "Použití: sudo bash scripts/capture.sh T01 CONF"
    exit 1
fi

IMPLEMENTATION="${IMPLEMENTATION^^}"

case "$IMPLEMENTATION" in
    CONF|AEL|LUA)
        ;;
    *)
        echo "[ERROR] Použij CONF, AEL nebo LUA."
        exit 1
        ;;
esac

# Kontrola ústředny

if ! systemctl is-active --quiet asterisk; then
    echo "[ERROR] Asterisk neběží."
    exit 1
fi

for tool in tcpdump tshark asterisk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] Chybí nástroj: $tool"
        exit 1
    fi
done

# Kontrola perzistentního úložiště

if [[ "$EVIDENCE_ROOT" == /data || "$EVIDENCE_ROOT" == /data/* ]]; then
    if ! mountpoint -q /data; then
        echo "[ERROR] Perzistentní disk /data není připojen."
        exit 1
    fi
fi

# Příprava adresářů

mkdir -p "$EVIDENCE_ROOT/$SCENARIO/$IMPLEMENTATION"

OUTPUT_DIR="$(mktemp -d \
    "$EVIDENCE_ROOT/$SCENARIO/$IMPLEMENTATION/${TIMESTAMP}.XXXXXX")"

mkdir -p "$OUTPUT_DIR"/{network,logs,system,dialplan,results}

# Ukončení záznamu

stop_capture() {

    if [[ -n "$CAPTURE_PID" ]]; then
        kill -TERM "$CAPTURE_PID" 2>/dev/null || true
        wait "$CAPTURE_PID" 2>/dev/null || true
        CAPTURE_PID=""
    fi

    if [[ -n "$LOG_PID" ]]; then
        kill -TERM "$LOG_PID" 2>/dev/null || true
        wait "$LOG_PID" 2>/dev/null || true
        LOG_PID=""
    fi

}

trap stop_capture EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Funkce pro zaznamenání stavu ústředny

snapshot() {

    local PHASE="$1"

    asterisk -rx "core show channels" \
        > "$OUTPUT_DIR/system/channels_$PHASE.txt"

    asterisk -rx "pjsip show endpoints" \
        > "$OUTPUT_DIR/system/endpoints_$PHASE.txt"

    asterisk -rx "pjsip show contacts" \
        > "$OUTPUT_DIR/system/contacts_$PHASE.txt"

    asterisk -rx "queue show support" \
        > "$OUTPUT_DIR/system/queue_$PHASE.txt"

    asterisk -rx "voicemail show users for support" \
        > "$OUTPUT_DIR/system/voicemail_$PHASE.txt"

    asterisk -rx "database show voip" \
        > "$OUTPUT_DIR/system/mode_$PHASE.txt"

}

echo "========================================"
echo "         VOIP EVIDENCE CAPTURE"
echo "========================================"

echo "[INFO] Scénář: $SCENARIO"
echo "[INFO] Implementace: $IMPLEMENTATION"
echo "[INFO] Výstup: $OUTPUT_DIR"

# Informace o prostředí

{
    echo "Scenario: $SCENARIO"
    echo "Implementation: $IMPLEMENTATION"
    echo "Started: $(date --iso-8601=seconds)"
    echo "Hostname: $(hostname)"
    echo "Architecture: $(uname -m)"
    echo "Kernel: $(uname -r)"
    echo "Asterisk: $(asterisk -V)"
    echo "Timezone: $(timedatectl show -p Timezone --value)"
    echo "Git commit: $(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$OUTPUT_DIR/system/environment.txt"

# Informace o dialplanech

asterisk -rx "dialplan show internal" \
    > "$OUTPUT_DIR/dialplan/internal.txt"

asterisk -rx "dialplan show support-conf" \
    > "$OUTPUT_DIR/dialplan/conf.txt"

asterisk -rx "dialplan show support-ael" \
    > "$OUTPUT_DIR/dialplan/ael.txt"

asterisk -rx "dialplan show support-lua" \
    > "$OUTPUT_DIR/dialplan/lua.txt"

asterisk -rx "module show" \
    > "$OUTPUT_DIR/system/modules.txt"

# Kontrolní součty nasazené konfigurace

sha256sum \
    /etc/asterisk/extensions.conf \
    /etc/asterisk/extensions.ael \
    /etc/asterisk/extensions.lua \
    /etc/asterisk/pjsip.conf \
    /etc/asterisk/queues.conf \
    /etc/asterisk/voicemail.conf \
    /etc/asterisk/rtp.conf \
    /etc/asterisk/modules.conf \
    > "$OUTPUT_DIR/system/config_sha256.txt"

# Stav před testem

snapshot before

# Zahájení záznamu logů

tail -n 0 -F /var/log/asterisk/full \
    > "$OUTPUT_DIR/logs/asterisk.log" \
    2> "$OUTPUT_DIR/logs/tail.log" &

LOG_PID=$!

# Zahájení záznamu SIP a RTP

tcpdump \
    -i any \
    -nn \
    -s 0 \
    -U \
    -Z root \
    -w "$OUTPUT_DIR/network/traffic.pcap" \
    'udp port 5060 or udp portrange 10000-20000' \
    > "$OUTPUT_DIR/logs/tcpdump.log" 2>&1 &

CAPTURE_PID=$!

sleep 1

if ! kill -0 "$CAPTURE_PID" 2>/dev/null; then
    echo "[ERROR] Nepodařilo se spustit tcpdump."
    cat "$OUTPUT_DIR/logs/tcpdump.log"
    exit 1
fi

echo
echo "========================================"
echo "[OK] Záznam byl zahájen."
echo "Proveď požadovaný testovací hovor."
echo "Po dokončení hovoru stiskni ENTER."
echo "========================================"

read -r

# Ukončení záznamu

stop_capture

echo "[OK] Záznam byl ukončen."

# Stav po testu

snapshot after

# Analýza SIP komunikace

tshark \
    -r "$OUTPUT_DIR/network/traffic.pcap" \
    -Y sip \
    > "$OUTPUT_DIR/network/sip.txt" \
    2> "$OUTPUT_DIR/logs/tshark.log"

# Analýza RTP streamů

tshark \
    -r "$OUTPUT_DIR/network/traffic.pcap" \
    -q -z rtp,streams \
    > "$OUTPUT_DIR/network/rtp_streams.txt" \
    2>> "$OUTPUT_DIR/logs/tshark.log"

# Statistiky komunikace

tshark \
    -r "$OUTPUT_DIR/network/traffic.pcap" \
    -q -z io,phs \
    > "$OUTPUT_DIR/network/statistics.txt" \
    2>> "$OUTPUT_DIR/logs/tshark.log"

# Diagnostické výpisy dialplanu

grep -E '\[(CONF|AEL|LUA)\]' \
    "$OUTPUT_DIR/logs/asterisk.log" \
    > "$OUTPUT_DIR/logs/dialplan_events.txt" || true

# Ruční vyhodnocení testu

echo
echo "Výsledek testovacího scénáře:"
echo "1 - PASS"
echo "2 - FAIL"
echo "3 - NOT EVALUATED"

read -r -p "Výsledek: " RESULT

case "$RESULT" in
    1) RESULT="PASS" ;;
    2) RESULT="FAIL" ;;
    *) RESULT="NOT EVALUATED" ;;
esac

read -r -p "Poznámka k testu: " NOTES

{
    echo "Scenario: $SCENARIO"
    echo "Implementation: $IMPLEMENTATION"
    echo "Result: $RESULT"
    echo "Notes: $NOTES"
    echo "Finished: $(date --iso-8601=seconds)"
} > "$OUTPUT_DIR/results/result.txt"

# Kontrolní součty

(
    cd "$OUTPUT_DIR"

    find . -type f ! -name SHA256SUMS \
        -print0 | sort -z | xargs -0 sha256sum \
        > SHA256SUMS
)

# Komprimace důkazového balíčku

ARCHIVE="${OUTPUT_DIR}.tar.gz"

tar -czf "$ARCHIVE" \
    -C "$(dirname "$OUTPUT_DIR")" \
    "$(basename "$OUTPUT_DIR")"

echo
echo "========================================"
echo "[OK] Důkazový balíček vytvořen."
echo "[INFO] Výsledek: $RESULT"
echo "[INFO] Adresář: $OUTPUT_DIR"
echo "[INFO] Archiv: $ARCHIVE"
echo "========================================"
