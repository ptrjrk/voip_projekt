#!/usr/bin/env bash

set -Eeuo pipefail
export LC_ALL=C

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

IMPLEMENTATION="${1:-}"
IMPLEMENTATION="${IMPLEMENTATION^^}"
DURATION="${2:-60}"

EVIDENCE_ROOT="${EVIDENCE_ROOT:-/data/voip_evidence}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

umask 077

# Kontrola oprávnění

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Spusť skript pomocí sudo."
    exit 1
fi

# Kontrola argumentů

case "$IMPLEMENTATION" in
    CONF|AEL|LUA|IDLE)
        ;;
    *)
        echo "Použití: sudo bash scripts/benchmark.sh CONF 60"
        echo "Implementace: CONF | AEL | LUA | IDLE"
        exit 1
        ;;
esac

if [[ ! "$DURATION" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] Délka měření musí být celé kladné číslo."
    exit 1
fi

# Kontrola úložiště

if [[ "$EVIDENCE_ROOT" == /data || "$EVIDENCE_ROOT" == /data/* ]]; then
    if ! mountpoint -q /data; then
        echo "[ERROR] Disk /data není připojen."
        exit 1
    fi
fi

# Kontrola Asterisku

if ! systemctl is-active --quiet asterisk; then
    echo "[ERROR] Asterisk neběží."
    exit 1
fi

PID="$(systemctl show asterisk -p MainPID --value)"

if [[ "$PID" -le 0 || ! -r "/proc/$PID/stat" ]]; then
    echo "[ERROR] Nelze identifikovat proces Asterisku."
    exit 1
fi

CLK_TCK="$(getconf CLK_TCK)"
CPU_CORES="$(nproc)"

# Příprava výstupu

mkdir -p "$EVIDENCE_ROOT/T14/$IMPLEMENTATION"

OUTPUT_DIR="$(mktemp -d \
    "$EVIDENCE_ROOT/T14/$IMPLEMENTATION/${TIMESTAMP}.XXXXXX")"

mkdir -p "$OUTPUT_DIR"/{system,results}

CSV="$OUTPUT_DIR/results/performance.csv"

# Funkce pro získání údajů o procesu

read_process() {
    local stat_line
    local stat_fields
    local -a fields

    IFS= read -r stat_line < "/proc/$PID/stat"

    stat_fields="${stat_line##*) }"

    read -r -a fields <<< "$stat_fields"

    PROC_TICKS=$((fields[11] + fields[12]))
    PROC_START="${fields[19]}"

    read -r RSS_KB THREADS < <(
        awk '
            /^VmRSS:/   { rss=$2 }
            /^Threads:/ { threads=$2 }
            END { print rss+0, threads+0 }
        ' "/proc/$PID/status"
    )
}

read_uptime() {
    read -r UPTIME _ < /proc/uptime
}

# Informace o prostředí

{
    echo "Scenario: T14"
    echo "Implementation: $IMPLEMENTATION"
    echo "Duration: $DURATION seconds"
    echo "Started: $(date --iso-8601=seconds)"
    echo "Hostname: $(hostname)"
    echo "Architecture: $(uname -m)"
    echo "Kernel: $(uname -r)"
    echo "Asterisk: $(asterisk -V)"
    echo "Asterisk PID: $PID"
    echo "CPU cores: $CPU_CORES"
    echo "Clock ticks: $CLK_TCK"
    echo "Git commit: $(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
} > "$OUTPUT_DIR/system/environment.txt"

free -k > "$OUTPUT_DIR/system/memory.txt"

sha256sum \
    /etc/asterisk/extensions.conf \
    /etc/asterisk/extensions.ael \
    /etc/asterisk/extensions.lua \
    /etc/asterisk/pjsip.conf \
    /etc/asterisk/queues.conf \
    /etc/asterisk/voicemail.conf \
    /etc/asterisk/logger.conf \
    > "$OUTPUT_DIR/system/config_sha256.txt"

# Stav před měřením

asterisk -rx "core show channels" \
    > "$OUTPUT_DIR/system/channels_before.txt"

asterisk -rx "queue show support" \
    > "$OUTPUT_DIR/system/queue_before.txt"

asterisk -rx "pjsip show contacts" \
    > "$OUTPUT_DIR/system/contacts_before.txt"

asterisk -rx "database show voip" \
    > "$OUTPUT_DIR/system/mode_before.txt"

# Příprava měření

echo "========================================"
echo "           VOIP BENCHMARK"
echo "========================================"
echo "[INFO] Implementace: $IMPLEMENTATION"
echo "[INFO] Délka měření: $DURATION sekund"
echo "[INFO] PID Asterisku: $PID"
echo "[INFO] Výstup: $OUTPUT_DIR"
echo
echo "Připrav testovací prostředí."
echo "Pro zahájení měření stiskni ENTER."

read -r

echo "elapsed_s,cpu_percent,cpu_normalized_percent,rss_kb,rss_mb,threads" \
    > "$CSV"

read_process
read_uptime

START_ID="$PROC_START"
START_UPTIME="$UPTIME"
PREV_UPTIME="$UPTIME"
PREV_TICKS="$PROC_TICKS"

echo "[OK] Měření zahájeno."

# Pravidelné měření

while true; do

    sleep 1

    read_process
    read_uptime

    if [[ "$PROC_START" != "$START_ID" ]]; then
        echo "[ERROR] Proces Asterisku byl nahrazen."
        exit 1
    fi

    ELAPSED="$(awk \
        -v now="$UPTIME" \
        -v start="$START_UPTIME" \
        'BEGIN { printf "%.3f", now-start }')"

    DELTA_TICKS=$((PROC_TICKS - PREV_TICKS))

    DELTA_TIME="$(awk \
        -v now="$UPTIME" \
        -v prev="$PREV_UPTIME" \
        'BEGIN { print now-prev }')"

    CPU="$(awk \
        -v ticks="$DELTA_TICKS" \
        -v hz="$CLK_TCK" \
        -v dt="$DELTA_TIME" \
        'BEGIN {
            if (dt>0)
                printf "%.3f", 100*ticks/(hz*dt)
            else
                print "0"
        }')"

    CPU_NORMALIZED="$(awk \
        -v cpu="$CPU" \
        -v cores="$CPU_CORES" \
        'BEGIN { printf "%.3f", cpu/cores }')"

    RSS_MB="$(awk \
        -v kb="$RSS_KB" \
        'BEGIN { printf "%.3f", kb/1024 }')"

    echo "$ELAPSED,$CPU,$CPU_NORMALIZED,$RSS_KB,$RSS_MB,$THREADS" \
        >> "$CSV"

    printf "Time: %7ss | CPU: %7s%% | RAM: %8s MiB | Threads: %s\n" \
        "$ELAPSED" "$CPU" "$RSS_MB" "$THREADS"

    PREV_TICKS="$PROC_TICKS"
    PREV_UPTIME="$UPTIME"

    if awk -v elapsed="$ELAPSED" -v duration="$DURATION" \
        'BEGIN { exit !(elapsed>=duration) }'; then
        break
    fi

done

echo "[OK] Měření dokončeno."

# Stav po měření

asterisk -rx "core show channels" \
    > "$OUTPUT_DIR/system/channels_after.txt"

asterisk -rx "queue show support" \
    > "$OUTPUT_DIR/system/queue_after.txt"

asterisk -rx "pjsip show contacts" \
    > "$OUTPUT_DIR/system/contacts_after.txt"

asterisk -rx "database show voip" \
    > "$OUTPUT_DIR/system/mode_after.txt"

# Výpočet souhrnných statistik

awk -F, '

NR > 1 {
    n++

    cpu_sum += $2
    normalized_sum += $3
    ram_sum += $5
    threads_sum += $6

    if (n == 1 || $2 > cpu_max) cpu_max = $2
    if (n == 1 || $2 < cpu_min) cpu_min = $2

    if (n == 1 || $5 > ram_max) ram_max = $5
    if (n == 1 || $5 < ram_min) ram_min = $5

    if (n == 1 || $6 > threads_max) threads_max = $6

    duration = $1
}

END {
    if (n == 0) exit 1

    printf "Samples: %d\n", n
    printf "Duration: %.3f s\n", duration

    printf "Average CPU: %.3f %%\n", cpu_sum/n
    printf "Minimum CPU: %.3f %%\n", cpu_min
    printf "Maximum CPU: %.3f %%\n", cpu_max

    printf "Average normalized CPU: %.3f %%\n", normalized_sum/n

    printf "Average RAM RSS: %.3f MiB\n", ram_sum/n
    printf "Minimum RAM RSS: %.3f MiB\n", ram_min
    printf "Maximum RAM RSS: %.3f MiB\n", ram_max

    printf "Average threads: %.2f\n", threads_sum/n
    printf "Maximum threads: %d\n", threads_max
}

' "$CSV" > "$OUTPUT_DIR/results/summary.txt"

# Poznámka k experimentu

read -r -p "Poznámka k měření: " NOTES

{
    echo "Scenario: T14"
    echo "Implementation: $IMPLEMENTATION"
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

# Komprimace výsledků

ARCHIVE="${OUTPUT_DIR}.tar.gz"

tar -czf "$ARCHIVE" \
    -C "$(dirname "$OUTPUT_DIR")" \
    "$(basename "$OUTPUT_DIR")"

echo
echo "========================================"
echo "             VÝSLEDKY"
echo "========================================"

cat "$OUTPUT_DIR/results/summary.txt"

echo "========================================"
echo "[OK] Adresář: $OUTPUT_DIR"
echo "[OK] Archiv: $ARCHIVE"
echo "========================================"
