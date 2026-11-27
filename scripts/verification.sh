#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

source "$PROJECT_DIR/.env"

PASSED=0
FAILED=0
WARNINGS=0

REQUIRED_MODULES=(
    pbx_config
    pbx_ael
    pbx_lua
    chan_pjsip
    res_pjsip
    res_rtp_asterisk
    res_musiconhold
    app_dial
    app_queue
    app_voicemail
    func_db
    func_callerid
    codec_alaw
    codec_ulaw
)

# Verification functions

pass() {
    echo "[PASS] $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "[FAIL] $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo "[WARN] $1"
    WARNINGS=$((WARNINGS + 1))
}

cli() {
    asterisk -rx "$1"
}

check_cli() {
    local description="$1"
    local command="$2"
    local pattern="$3"
    local output

    if output="$(cli "$command" 2>&1)" &&
       grep -Eq "$pattern" <<< "$output"; then
        pass "$description"
    else
        fail "$description"
        echo "$output"
    fi
}

echo "========================================"
echo "          VERIFIKACE ASTERISKU"
echo "========================================"

# Kontrola oprávnění

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Jsou vyžadována oprávnění root."
    exit 1
fi

# ========================================
# 1. System service
# ========================================

echo
echo "[1/8] Kontrola systémové služby"

if systemctl is-active --quiet asterisk; then
    pass "Služba Asterisk běží"
else
    fail "Služba Asterisk neběží"
    journalctl -u asterisk -n 30 --no-pager
    exit 1
fi

if systemctl is-enabled --quiet asterisk; then
    pass "Automatické spouštění služby"
else
    warn "Automatické spouštění není povoleno"
fi

check_cli \
    "Dostupnost Asterisk CLI" \
    "core show uptime" \
    "System uptime"

# ========================================
# 2. Required modules
# ========================================

echo
echo "[2/8] Kontrola požadovaných modulů"

for module in "${REQUIRED_MODULES[@]}"; do

    check_cli \
        "Modul $module" \
        "module show like $module.so" \
        "^${module}\.so[[:space:]].*Running"

done

# ========================================
# 3. PJSIP endpoints
# ========================================

echo
echo "[3/8] Kontrola SIP účtů"

for endpoint in 1001 1002 1003; do

    check_cli \
        "SIP účet $endpoint" \
        "pjsip show endpoint $endpoint" \
        "Endpoint:[[:space:]]+${endpoint}([[:space:]/]|$)"

done

echo
echo "[INFO] Registrovaná zařízení:"

cli "pjsip show contacts" || true

# ========================================
# 4. Dialplan
# ========================================

echo
echo "[4/8] Kontrola dialplanů"

check_cli \
    "CONF - context support-conf" \
    "dialplan show 2001@support-conf" \
    "'2001'[[:space:]]*=>"

check_cli \
    "AEL - context support-ael" \
    "dialplan show 2002@support-ael" \
    "'2002'[[:space:]]*=>"

check_cli \
    "Lua - context support-lua" \
    "dialplan show support-lua" \
    "Lua/|2003"

check_cli \
    "CONF - routing from internal" \
    "dialplan show internal" \
    "support-conf"

check_cli \
    "AEL - routing from internal" \
    "dialplan show internal" \
    "support-ael"

check_cli \
    "Lua - routing from internal" \
    "dialplan show internal" \
    "support-lua"

check_cli \
    "Voicemail access - 3000" \
    "dialplan show 3000@internal" \
    "'3000'[[:space:]]*=>"

# ========================================
# 5. Queue
# ========================================

echo
echo "[5/8] Kontrola telefonní fronty"

check_cli \
    "Fronta support" \
    "queue show support" \
    "^support[[:space:]]+has"

check_cli \
    "Strategie ringall" \
    "queue show support" \
    "ringall"

check_cli \
    "Operátor 1002" \
    "queue show support" \
    "PJSIP/1002"

check_cli \
    "Operátor 1003" \
    "queue show support" \
    "PJSIP/1003"

# ========================================
# 6. Voicemail
# ========================================

echo
echo "[6/8] Kontrola hlasové schránky"

check_cli \
    "Hlasová schránka 3000@support" \
    "voicemail show users for support" \
    "(^|[[:space:]])3000([[:space:]]|$)"

# ========================================
# 7. Network
# ========================================

echo
echo "[7/8] Kontrola síťových služeb"

if ss -H -lunp 'sport = :5060' | grep -q asterisk; then
    pass "Asterisk naslouchá na UDP portu 5060"
else
    fail "SIP port 5060 není dostupný"
fi

check_cli \
    "PJSIP UDP transport" \
    "pjsip show transports" \
    "transport-udp"

if grep -Eq '^rtpstart[[:space:]]*=[[:space:]]*10000$' \
        /etc/asterisk/rtp.conf &&
   grep -Eq '^rtpend[[:space:]]*=[[:space:]]*20000$' \
        /etc/asterisk/rtp.conf; then

    pass "Konfigurace RTP portů 10000-20000"

else

    fail "Nesprávný rozsah RTP portů"

fi

# ========================================
# 8. System configuration
# ========================================

echo
echo "[8/8] Kontrola konfigurace systému"

if [[ "$(timedatectl show -p Timezone --value)" == "Europe/Prague" ]]; then
    pass "Časová zóna Europe/Prague"
else
    fail "Nesprávná časová zóna"
fi

check_cli \
    "Demonstrační režim" \
    "database get voip mode" \
    "Value: (auto|open|closed)"

if [[ -f /var/log/asterisk/full ]]; then
    pass "Diagnostický log Asterisku"
else
    warn "Diagnostický log zatím neexistuje"
fi

# ========================================
# Results
# ========================================

echo
echo "========================================"
echo "          VÝSLEDKY VERIFIKACE"
echo "========================================"
echo "Úspěšné kontroly: $PASSED"
echo "Neúspěšné kontroly: $FAILED"
echo "Varování: $WARNINGS"
echo "========================================"

if (( FAILED > 0 )); then

    echo "[ERROR] Verifikace projektu selhala."
    exit 1

fi

echo "[OK] Verifikace projektu dokončena."
echo "[OK] Telefonní ústředna je připravena k testování."

exit 0
