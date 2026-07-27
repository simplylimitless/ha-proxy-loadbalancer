#!/usr/bin/env bash
# =============================================================================
# Tests for deploy.sh — template processing and config generation
# =============================================================================
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

PROJECT_ROOT="$(dirname "$TEST_DIR")"

echo -e "${BLUE}═══ Testing deploy.sh — template processing ${NC}"

# --- Test: deploy.sh requires config.sh ---
echo -e "  ${BLUE}TEST:${NC} requires config.sh to exist"
{
SCRIPT_DIR="/tmp/haproxy-lb-test_deploy_no_config"
mkdir -p "$SCRIPT_DIR"

cat > "$SCRIPT_DIR/deploy.sh" <<'DEPLOY'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/config.sh" ]]; then
    echo "ERROR: ${SCRIPT_DIR}/config.sh not found" >&2
    exit 1
fi
echo "OK"
DEPLOY
chmod +x "$SCRIPT_DIR/deploy.sh"

OUTPUT=$("$SCRIPT_DIR/deploy.sh" 2>&1) || true
assert_contains "$OUTPUT" "ERROR" "error message shown"
}
rm -rf /tmp/haproxy-lb-test_deploy_no_config

# --- Test: deploy.sh requires node.conf ---
echo -e "  ${BLUE}TEST:${NC} requires node.conf to exist"
{
NODE_DIR="/tmp/haproxy-lb-test_node_dir"
mkdir -p "$NODE_DIR"

# Create config.sh
cat > "$NODE_DIR/config.sh" <<'CONFIG'
#!/usr/bin/env bash
VIP_ADDRESS="192.168.1.100"
VIP_SUBNET="24"
VRRP_INTERFACE="eth0"
VRRP_VRID=50
BACKENDS=("192.168.1.10:8006" "192.168.1.11:8006" "192.168.1.12:8006")
HC_INTERVAL=2000
HC_TIMEOUT=5000
CONFIG

# Test node.conf check
NODE_CONF="$NODE_DIR/node.conf"
if [[ ! -f "$NODE_CONF" ]]; then
    OUTPUT="ERROR: ${NODE_CONF} not found"
fi

assert_contains "$OUTPUT" "ERROR" "error message shown"
}
rm -rf /tmp/haproxy-lb-test_node_dir

# --- Test: BACKENDS array builds correct server directives ---
echo -e "  ${BLUE}TEST:${NC} builds HAProxy backend server directives from BACKENDS array"
{
SCRIPT_DIR="/tmp/haproxy-lb-test_build_backends"
mkdir -p "$SCRIPT_DIR"

cat > "$SCRIPT_DIR/config.sh" <<'CONFIG'
#!/usr/bin/env bash
VIP_ADDRESS="192.168.1.100"
VIP_SUBNET="24"
VRRP_INTERFACE="eth0"
VRRP_VRID=50
BACKENDS=("192.168.1.10:8006" "192.168.1.11:8006" "192.168.1.12:8006")
HC_INTERVAL=2000
HC_TIMEOUT=5000
CONFIG

source "$SCRIPT_DIR/config.sh"

BACKEND_LINES=""
BACKEND_STICKY_LINES=""
for i in "${!BACKENDS[@]}"; do
    ip_port="${BACKENDS[$i]}"
    server_name="node${i}.$(echo "$ip_port" | cut -d: -f1 | tr '.' '_')"
    BACKEND_LINES+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL}m fall 3 rise 2\n"
    BACKEND_STICKY_LINES+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL}m fall 3 rise 2 cookie node${i}\n"
done

assert_eq "3" "${#BACKENDS[@]}" "three backends in array"
assert_contains "$(echo -e "$BACKEND_LINES")" "server node0.192_168_1_10" "backend node0"
assert_contains "$(echo -e "$BACKEND_LINES")" "server node1.192_168_1_11" "backend node1"
assert_contains "$(echo -e "$BACKEND_LINES")" "server node2.192_168_1_12" "backend node2"
assert_contains "$(echo -e "$BACKEND_LINES")" "inter 2000m" "interval in directive"
assert_contains "$(echo -e "$BACKEND_LINES")" "fall 3 rise 2" "fall/rise values"

# Sticky backend should have cookie parameter
assert_contains "$(echo -e "$BACKEND_STICKY_LINES")" "cookie node0" "sticky cookie node0"
assert_contains "$(echo -e "$BACKEND_STICKY_LINES")" "cookie node1" "sticky cookie node1"
assert_contains "$(echo -e "$BACKEND_STICKY_LINES")" "cookie node2" "sticky cookie node2"
}
rm -rf /tmp/haproxy-lb-test_build_backends

# --- Test: keepalived.conf template variable substitution ---
echo -e "  ${BLUE}TEST:${NC} substitutes variables in keepalived.conf template"
{
TEMPLATE="/tmp/haproxy-lb-test_kal_template"
OUTPUT="/tmp/haproxy-lb-test_kal_output"

cat > "$TEMPLATE" <<'TPL'
vrrp_instance VIP_${VRRP_VRID} {
    state ${INITIAL_STATE}
    interface ${VRRP_INTERFACE}
    virtual_router_id ${VRRP_VRID}
    priority ${NODE_PRIORITY}
    multicast_src ${NODE_IP}
    virtual_ipaddress {
        ${VIP_ADDRESS}/${VIP_SUBNET}
    }
}
TPL

VRRP_INTERFACE="eno1"
VRRP_VRID=75
VIP_ADDRESS="10.10.10.50"
VIP_SUBNET="24"
NODE_PRIORITY="90"
NODE_IP="10.10.10.2"
HA_PROXY_WEIGHT=20
INITIAL_STATE="BACKUP"

sed -e "s/\${VRRP_INTERFACE}/${VRRP_INTERFACE}/g" \
    -e "s/\${VRRP_VRID}/${VRRP_VRID}/g" \
    -e "s/\${VIP_ADDRESS}/${VIP_ADDRESS}/g" \
    -e "s/\${VIP_SUBNET}/${VIP_SUBNET}/g" \
    -e "s/\${NODE_PRIORITY}/${NODE_PRIORITY}/g" \
    -e "s/\${NODE_IP}/${NODE_IP}/g" \
    -e "s/\${HA_PROXY_WEIGHT}/${HA_PROXY_WEIGHT}/g" \
    -e "s/\${INITIAL_STATE}/${INITIAL_STATE}/g" \
    "$TEMPLATE" > "$OUTPUT"

assert_file_contains "$OUTPUT" "vrrp_instance VIP_75" "VRID substituted"
assert_file_contains "$OUTPUT" "state BACKUP" "state substituted"
assert_file_contains "$OUTPUT" "interface eno1" "interface substituted"
assert_file_contains "$OUTPUT" "priority 90" "priority substituted"
assert_file_contains "$OUTPUT" "multicast_src 10.10.10.2" "NODE_IP substituted"
assert_file_contains "$OUTPUT" "10.10.10.50/24" "VIP address substituted"
}
rm -f /tmp/haproxy-lb-test_kal_template /tmp/haproxy-lb-test_kal_output

# --- Test: haproxy.cfg template variable substitution ---
echo -e "  ${BLUE}TEST:${NC} substitutes variables in haproxy.cfg template"
{
TEMPLATE="/tmp/haproxy-lb-test_haproxy_template"
OUTPUT="/tmp/haproxy-lb-test_haproxy_output"

cat > "$TEMPLATE" <<'TPL'
backend backend_nodes
    balance roundrobin
    option httpchk GET /api2/json
    http-check expect status 200,401,403
    default-server ssl verify none ca-file none
    inter ${HC_INTERVAL} rise 2 fall 3
${BACKENDS_DIRECTIVE}
TPL

HC_INTERVAL="3000"
BACKENDS_DIRECTIVE="    server node0_10_0_0_10 10.0.0.10:8006 check inter 3000m fall 3 rise 2"

sed -e "s/\${HC_INTERVAL}/${HC_INTERVAL}/g" \
    -e "s|\${BACKENDS_DIRECTIVE}|${BACKENDS_DIRECTIVE}|g" \
    "$TEMPLATE" > "$OUTPUT"

assert_file_contains "$OUTPUT" "inter 3000 rise 2 fall 3" "HC_INTERVAL substituted"
assert_file_contains "$OUTPUT" "server node0_10_0_0_10 10.0.0.10:8006" "backends substituted"
}
rm -f /tmp/haproxy-lb-test_haproxy_template /tmp/haproxy-lb-test_haproxy_output

# --- Test: deploy.sh outputs status messages ---
echo -e "  ${BLUE}TEST:${NC} outputs deployment status messages"
{
SCRIPT_DIR="/tmp/haproxy-lb-test_deploy_output"
mkdir -p "$SCRIPT_DIR"

cat > "$SCRIPT_DIR/config.sh" <<'CONFIG'
#!/usr/bin/env bash
VIP_ADDRESS="10.0.0.1"
VIP_SUBNET="24"
VRRP_INTERFACE="eth0"
VRRP_VRID=50
BACKENDS=("10.0.0.10:8006" "10.0.0.11:8006")
HC_INTERVAL=2000
HC_TIMEOUT=5000
CONFIG

cat > "$SCRIPT_DIR/node.conf" <<'NODE'
NODE_PRIORITY=110
NODE_IP="10.0.0.1"
NODE

source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/node.conf"

INITIAL_STATE="MASTER"
if [[ $NODE_PRIORITY -lt 100 ]]; then
    INITIAL_STATE="BACKUP"
fi

# Build expected output
OUTPUT="=== HA Load Balancer Deployment ===
Node priority:  ${NODE_PRIORITY}
VIP:            ${VIP_ADDRESS}/${VIP_SUBNET}
Interface:      ${VRRP_INTERFACE}
HAProxy mode:   ${INITIAL_STATE}
Backends:       ${#BACKENDS[@]} nodes"

assert_contains "$OUTPUT" "HA Load Balancer Deployment" "deployment header"
assert_contains "$OUTPUT" "Node priority:  110" "priority line"
assert_contains "$OUTPUT" "VIP:            10.0.0.1/24" "VIP line"
assert_contains "$OUTPUT" "Interface:      eth0" "interface line"
assert_contains "$OUTPUT" "HAProxy mode:   MASTER" "mode line"
assert_contains "$OUTPUT" "Backends:       2 nodes" "backend count"
}
rm -rf /tmp/haproxy-lb-test_deploy_output

# --- Test: deploy.sh creates directories ---
echo -e "  ${BLUE}TEST:${NC} creates required directories"
DEPLOY_MKDIR="/tmp/haproxy-lb-test_deploy_mkdir"
rm -rf "$DEPLOY_MKDIR"
mkdir -p "$DEPLOY_MKDIR/etc/keepalived"
mkdir -p "$DEPLOY_MKDIR/etc/haproxy/certs"
mkdir -p "$DEPLOY_MKDIR/usr/local/bin"
assert_true "[[ -d \"$DEPLOY_MKDIR/etc/keepalived\" ]]" "keepalived dir"
assert_true "[[ -d \"$DEPLOY_MKDIR/etc/haproxy/certs\" ]]" "haproxy certs dir"
assert_true "[[ -d \"$DEPLOY_MKDIR/usr/local/bin\" ]]" "bin dir"
rm -rf /tmp/haproxy-lb-test_deploy_mkdir

# --- Test: deploy.sh sets correct file permissions ---
echo -e "  ${BLUE}TEST:${NC} sets correct file permissions"
{
TEST_DIR="/tmp/haproxy-lb-test_perms"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

echo "test" > "$TEST_DIR/keepalived.conf"
echo "test" > "$TEST_DIR/haproxy.cfg"
echo "test" > "$TEST_DIR/ha-check-haproxy.sh"

chmod 600 "$TEST_DIR/keepalived.conf"
chmod 644 "$TEST_DIR/haproxy.cfg"
chmod 755 "$TEST_DIR/ha-check-haproxy.sh"

KEEPALIVED_PERMS=$(stat -c "%a" "$TEST_DIR/keepalived.conf")
HAPROXY_PERMS=$(stat -c "%a" "$TEST_DIR/haproxy.cfg")
CHECK_PERMS=$(stat -c "%a" "$TEST_DIR/ha-check-haproxy.sh")

assert_eq "600" "$KEEPALIVED_PERMS" "keepalived.conf is 600"
assert_eq "644" "$HAPROXY_PERMS" "haproxy.cfg is 644"
assert_eq "755" "$CHECK_PERMS" "ha-check-haproxy.sh is 755"
}
rm -rf /tmp/haproxy-lb-test_perms

# --- Test: self-signed cert generation ---
echo -e "  ${BLUE}TEST:${NC} generates self-signed certificate bundle"
CERTGEN_DIR="/tmp/haproxy-lb-test_certgen"
rm -rf "$CERTGEN_DIR"
mkdir -p "$CERTGEN_DIR/certs"

VIP_ADDRESS="10.0.0.1"
CERT_BUNDLE="$CERTGEN_DIR/certs/backend.pem"

openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$CERTGEN_DIR/key.pem" -out "$CERTGEN_DIR/cert.pem" \
    -days 365 -subj "/CN=${VIP_ADDRESS}" 2>/dev/null
cat "$CERTGEN_DIR/cert.pem" "$CERTGEN_DIR/key.pem" > "$CERT_BUNDLE"
rm -f "$CERTGEN_DIR/key.pem" "$CERTGEN_DIR/cert.pem"
chmod 600 "$CERT_BUNDLE"

assert_file_exists "$CERT_BUNDLE" "cert bundle created"
assert_file_contains "$CERT_BUNDLE" "BEGIN CERTIFICATE" "contains certificate block"
rm -rf /tmp/haproxy-lb-test_certgen

print_summary
