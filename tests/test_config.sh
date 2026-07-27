#!/usr/bin/env bash
# =============================================================================
# Tests for config.sh — shared configuration variables
# =============================================================================
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

PROJECT_ROOT="$(dirname "$TEST_DIR")"

echo -e "${BLUE}═══ Testing config.sh — configuration variables ${NC}"

# --- Test: config.sh sets expected default values ---
echo -e "  ${BLUE}TEST:${NC} config.sh sets expected defaults"
{
CONFIG="$PROJECT_ROOT/config.sh"
source "$CONFIG"

assert_eq "192.168.1.100" "$VIP_ADDRESS" "VIP address"
assert_eq "24" "$VIP_SUBNET" "VIP subnet"
assert_eq "eth0" "$VRRP_INTERFACE" "VRRP interface"
assert_eq "50" "$VRRP_VRID" "VRRP VRID"
assert_eq "2000" "$HC_INTERVAL" "health check interval"
assert_eq "5000" "$HC_TIMEOUT" "health check timeout"
assert_eq "1.1" "$HC_HTTP_VERSION" "HTTP version for health checks"
}

# --- Test: BACKENDS array has correct structure ---
echo -e "  ${BLUE}TEST:${NC} config.sh BACKENDS array has 3 entries"
{
CONFIG="$PROJECT_ROOT/config.sh"
source "$CONFIG"

assert_eq "3" "${#BACKENDS[@]}" "three backends defined"
assert_contains "${BACKENDS[0]}" ":80" "backend 0 has port 80"
assert_contains "${BACKENDS[1]}" ":80" "backend 1 has port 80"
assert_contains "${BACKENDS[2]}" ":80" "backend 2 has port 80"
}

# --- Test: BACKENDS entries have valid IP:PORT format ---
echo -e "  ${BLUE}TEST:${NC} config.sh BACKENDS entries have valid IP:PORT format"
{
CONFIG="$PROJECT_ROOT/config.sh"
source "$CONFIG"

for i in "${!BACKENDS[@]}"; do
    entry="${BACKENDS[$i]}"
    if [[ "$entry" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC} — backend[$i] = $entry"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC} — backend[$i] = $entry (invalid format)"
    fi
done
}

# --- Test: BACKEND_USER defaults to empty ---
echo -e "  ${BLUE}TEST:${NC} BACKEND_USER defaults to empty"
{
CONFIG="$PROJECT_ROOT/config.sh"
source "$CONFIG"
assert_eq "" "$BACKEND_USER" "BACKEND_USER default"
}

# --- Test: SMTP settings are commented out by default ---
echo -e "  ${BLUE}TEST:${NC} SMTP settings are commented out by default"
{
CONFIG="$PROJECT_ROOT/config.sh"

# Check that SMTP lines exist but are commented (not active assignments)
UNCOMMENTED_SMTP=$(grep -c "^SMTP_SERVER" "$CONFIG" || true)
COMMENTED_SMTP=$(grep -c "^# SMTP_SERVER" "$CONFIG" || true)
UNCOMMENTED_ALERT=$(grep -c "^ALERT_EMAIL" "$CONFIG" || true)
COMMENTED_ALERT=$(grep -c "^# ALERT_EMAIL" "$CONFIG" || true)

assert_eq "0" "$UNCOMMENTED_SMTP" "SMTP_SERVER not uncommented"
assert_gt "$COMMENTED_SMTP" "0" "SMTP_SERVER is commented"
assert_eq "0" "$UNCOMMENTED_ALERT" "ALERT_EMAIL not uncommented"
assert_gt "$COMMENTED_ALERT" "0" "ALERT_EMAIL is commented"
}

# --- Test: Multicast source IP is set ---
echo -e "  ${BLUE}TEST:${NC} VRRP multicast_src is set"
{
CONFIG="$PROJECT_ROOT/config.sh"
source "$CONFIG"
assert_contains "$VRRP_MULTICAST_SRC" "192.168.1" "multicast source starts with 192.168.1"
}

# --- Test: Validating IP addresses in config ---
echo -e "  ${BLUE}TEST:${NC} validates IP address format in BACKENDS"
{
CONFIG="$PROJECT_ROOT/config.sh"
source "$CONFIG"

VALID=true
for i in "${!BACKENDS[@]}"; do
    entry="${BACKENDS[$i]}"
    ip="${entry%%:*}"
    port="${entry##*:}"

    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ "$octet" -lt 0 || "$octet" -gt 255 ]]; then
            VALID=false
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo -e "  ${RED}FAIL${NC} — backend[$i]: octet $octet out of range"
            break 2
        fi
    done

    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        VALID=false
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC} — backend[$i]: port $port out of range"
    fi
done

if $VALID; then
    assert_true "true" "all backends have valid IPs and ports"
fi
}

print_summary
