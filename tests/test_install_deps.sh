#!/usr/bin/env bash
# =============================================================================
# Tests for install-dependencies.sh — package installation logic
# =============================================================================
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

PROJECT_ROOT="$(dirname "$TEST_DIR")"
INSTALL_SCRIPT="$PROJECT_ROOT/install-dependencies.sh"

echo -e "${BLUE}═══ Testing install-dependencies.sh — package installation ${NC}"

# --- Test: Script exists and is executable ---
echo -e "  ${BLUE}TEST:${NC} install-dependencies.sh exists and is executable"
{
assert_file_exists "$INSTALL_SCRIPT" "script exists"

PERMS=$(stat -c "%a" "$INSTALL_SCRIPT")
# File is 775 (group-writable in container); just verify it's executable
if [[ -x "$INSTALL_SCRIPT" ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC} — script is executable (perms: $PERMS)"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}FAIL${NC} — script not executable (perms: $PERMS)"
fi
}

# --- Test: Script has correct shebang and strict mode ---
echo -e "  ${BLUE}TEST:${NC} install-dependencies.sh has correct shebang and strict mode"
{
SHEBANG=$(head -1 "$INSTALL_SCRIPT")
assert_eq '#!/usr/bin/env bash' "$SHEBANG" "correct shebang"

CONTENT=$(cat "$INSTALL_SCRIPT")
assert_contains "$CONTENT" "set -euo pipefail" "strict mode enabled"
}

# --- Test: Installs expected packages ---
echo -e "  ${BLUE}TEST:${NC} installs required packages"
{
CONTENT=$(cat "$INSTALL_SCRIPT")

for pkg in keepalived haproxy socat openssl iproute2 psmisc; do
    if echo "$CONTENT" | grep -q "$pkg"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC} — package $pkg in install list"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC} — package $pkg NOT in install list"
    fi
done
}

# --- Test: Configures sysctl parameters ---
echo -e "  ${BLUE}TEST:${NC} configures sysctl parameters"
{
CONTENT=$(cat "$INSTALL_SCRIPT")
assert_contains "$CONTENT" "99-ha-lb.conf" "sysctl config file"
assert_contains "$CONTENT" "net.ipv4.ip_nonlocal_bind" "ip_nonlocal_bind sysctl"
assert_contains "$CONTENT" "net.ipv4.vrrp_mcast_group4" "vrrp_mcast_group4 sysctl"
assert_contains "$CONTENT" "224.0.0.18" "VRRP multicast address"
assert_contains "$CONTENT" "sysctl -p" "applies sysctl"
}

# --- Test: Enables HAProxy in /etc/default/haproxy ---
echo -e "  ${BLUE}TEST:${NC} enables HAProxy in /etc/default/haproxy"
{
CONTENT=$(cat "$INSTALL_SCRIPT")
assert_contains "$CONTENT" "ENABLED=1" "HAProxy ENABLED setting"
assert_contains "$CONTENT" "/etc/default/haproxy" "haproxy defaults file"
}

# --- Test: Creates keepalived directory ---
echo -e "  ${BLUE}TEST:${NC} creates keepalived config directory"
{
CONTENT=$(cat "$INSTALL_SCRIPT")
assert_contains "$CONTENT" "mkdir -p /etc/keepalived" "keepalived directory creation"
}

# --- Test: Uses apt-get update before install ---
echo -e "  ${BLUE}TEST:${NC} runs apt-get update before install"
{
CONTENT=$(cat "$INSTALL_SCRIPT")
assert_contains "$CONTENT" "apt-get update" "apt-get update run"
assert_contains "$CONTENT" "--no-install-recommends" "no-recommends flag"
}

# --- Test: Sysctl config uses heredoc ---
echo -e "  ${BLUE}TEST:${NC} sysctl config uses heredoc"
{
CONTENT=$(cat "$INSTALL_SCRIPT")
assert_contains "$CONTENT" "cat >" "heredoc write"
assert_contains "$CONTENT" "SYSCTL" "heredoc delimiter"
}

print_summary
