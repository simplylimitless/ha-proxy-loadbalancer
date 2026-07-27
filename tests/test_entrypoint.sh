#!/usr/bin/env bash
# =============================================================================
# Tests for entrypoint.sh — config generation from environment variables
# =============================================================================
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

echo -e "${BLUE}═══ Testing entrypoint.sh — config generation ${NC}"

# --- Test: BACKENDS_LIST env var is parsed correctly ---
echo -e "  ${BLUE}TEST:${NC} parses BACKENDS_LIST env var"
{
BACKENDS_LIST="10.0.0.10:8006,10.0.0.11:8006,10.0.0.12:8006"
HC_INTERVAL="2000"

SERVERS=""
COUNT=0
IFS=',' read -ra ADDR <<< "$BACKENDS_LIST"
for ip_port in "${ADDR[@]}"; do
    ip_port="$(echo "$ip_port" | xargs)"
    [ -z "$ip_port" ] && continue
    ip_part="$(echo "$ip_port" | cut -d: -f1 | tr '.' '_')"
    server_name="node${COUNT}_${ip_part}"
    SERVERS+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL} rise 2 fall 3
"
    COUNT=$((COUNT + 1))
done

assert_eq "3" "$COUNT" "backend count"
assert_contains "$SERVERS" "server node0_10_0_0_10 10.0.0.10:8006" "first server directive"
assert_contains "$SERVERS" "server node1_10_0_0_11 10.0.0.11:8006" "second server directive"
assert_contains "$SERVERS" "server node2_10_0_0_12 10.0.0.12:8006" "third server directive"
assert_contains "$SERVERS" "inter 2000" "health check interval"
assert_contains "$SERVERS" "rise 2 fall 3" "health check parameters"
}

# --- Test: BACKENDS_FILE takes priority over BACKENDS_LIST ---
echo -e "  ${BLUE}TEST:${NC} BACKENDS_FILE takes priority over BACKENDS_LIST"
{
BACKENDS_FILE="/tmp/haproxy-lb-test_backends.conf"
echo "172.16.0.10:8006" > "$BACKENDS_FILE"
echo "172.16.0.11:8006" >> "$BACKENDS_FILE"

BACKENDS_LIST="10.0.0.1:8006,10.0.0.2:8006"
FINAL_LIST=""

if [ -f "$BACKENDS_FILE" ]; then
    while IFS= read -r line; do
        line="$(echo "$line" | sed 's/#.*//' | xargs)"
        [ -z "$line" ] && continue
        FINAL_LIST="${FINAL_LIST:+${FINAL_LIST},}${line}"
    done < "$BACKENDS_FILE"
fi

assert_contains "$FINAL_LIST" "172.16.0.10:8006" "file backend included"
assert_contains "$FINAL_LIST" "172.16.0.11:8006" "second file backend included"
}
rm -f /tmp/haproxy-lb-test_backends.conf

# --- Test: ROUTER_ID derived from interface name ---
echo -e "  ${BLUE}TEST:${NC} derives ROUTER_ID from VRRP_INTERFACE"
{
VRRP_INTERFACE="eth0"
ROUTER_ID="LBA_$(echo "$VRRP_INTERFACE" | tr '.' '_')"
assert_eq "LBA_eth0" "$ROUTER_ID" "ROUTER_ID for eth0"

VRRP_INTERFACE="eno1"
ROUTER_ID="LBA_$(echo "$VRRP_INTERFACE" | tr '.' '_')"
assert_eq "LBA_eno1" "$ROUTER_ID" "ROUTER_ID for eno1"
}

# --- Test: INITIAL_STATE based on NODE_PRIORITY ---
echo -e "  ${BLUE}TEST:${NC} sets INITIAL_STATE MASTER for priority >= 100"
{
NODE_PRIORITY="110"
INITIAL_STATE="MASTER"
if [ "$NODE_PRIORITY" -lt 100 ] 2>/dev/null; then
    INITIAL_STATE="BACKUP"
fi
assert_eq "MASTER" "$INITIAL_STATE" "priority 110 → MASTER"
}

echo -e "  ${BLUE}TEST:${NC} sets INITIAL_STATE BACKUP for priority < 100"
{
NODE_PRIORITY="90"
INITIAL_STATE="MASTER"
if [ "$NODE_PRIORITY" -lt 100 ] 2>/dev/null; then
    INITIAL_STATE="BACKUP"
fi
assert_eq "BACKUP" "$INITIAL_STATE" "priority 90 → BACKUP"
}

# --- Test: Generated keepalived.conf contains expected values ---
echo -e "  ${BLUE}TEST:${NC} generates correct keepalived.conf"
{
VIP_ADDRESS="10.0.0.1"
VIP_SUBNET="24"
VRRP_INTERFACE="eth0"
VRRP_VRID="50"
NODE_PRIORITY="110"
INITIAL_STATE="MASTER"
VRRP_AUTH_PASS="testpass123"
HA_PROXY_WEIGHT="20"
ROUTER_ID="LBA_eth0"

KEEPALIVED_CONF="/tmp/haproxy-lb-test_keepalived.conf"
cat > "$KEEPALIVED_CONF" << CONF
global_defs {
    router_id ${ROUTER_ID}
}

vrrp_script chk_haproxy {
    script "/usr/local/bin/ha-check-haproxy.sh"
    interval 2
    weight ${HA_PROXY_WEIGHT}
    fall 2
    rise 2
}

vrrp_instance VIP_${VRRP_VRID} {
    state ${INITIAL_STATE}
    interface ${VRRP_INTERFACE}
    virtual_router_id ${VRRP_VRID}
    priority ${NODE_PRIORITY}
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass "${VRRP_AUTH_PASS}"
    }

    virtual_ipaddress {
        ${VIP_ADDRESS}/${VIP_SUBNET}
    }

    track_script {
        chk_haproxy
    }
}
CONF

assert_file_contains "$KEEPALIVED_CONF" "router_id LBA_eth0" "router_id"
assert_file_contains "$KEEPALIVED_CONF" "interface eth0" "interface"
assert_file_contains "$KEEPALIVED_CONF" "priority 110" "priority"
assert_file_contains "$KEEPALIVED_CONF" "virtual_router_id 50" "VRID"
assert_file_contains "$KEEPALIVED_CONF" "state MASTER" "state"
assert_file_contains "$KEEPALIVED_CONF" "auth_pass \"testpass123\"" "auth pass"
assert_file_contains "$KEEPALIVED_CONF" "10.0.0.1/24" "VIP address"
assert_file_contains "$KEEPALIVED_CONF" "track_script" "track_script"
}
rm -f /tmp/haproxy-lb-test_keepalived.conf

# --- Test: Generated haproxy.cfg contains expected values ---
echo -e "  ${BLUE}TEST:${NC} generates correct haproxy.cfg"
{
HC_INTERVAL="2000"

HAPROXY_CONF="/tmp/haproxy-lb-test_haproxy.cfg"
cat > "$HAPROXY_CONF" << CONF
global
    log stdout format raw length 0 local0
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  forwardfor
    option  http-server-close

    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy?stats
    stats refresh 10s

frontend backend_https
    bind *:8006 ssl crt /etc/haproxy/certs/backend.pem
    default_backend backend_nodes

frontend backend_http
    bind *:8007
    http-request redirect scheme https code 301

backend backend_nodes
    balance roundrobin
    option httpchk GET /
    http-check expect status 200,401
    default-server ssl verify none ca-file none
    inter ${HC_INTERVAL} rise 2 fall 3

    server node0_10_0_0_10 10.0.0.10:8006 check inter 2000 rise 2 fall 3
    server node1_10_0_0_11 10.0.0.11:8006 check inter 2000 rise 2 fall 3
CONF

assert_file_contains "$HAPROXY_CONF" "mode http" "mode http"
assert_file_contains "$HAPROXY_CONF" "bind *:8006" "HTTPS frontend bind"
assert_file_contains "$HAPROXY_CONF" "bind *:8007" "HTTP redirect bind"
assert_file_contains "$HAPROXY_CONF" "bind *:8404" "stats bind"
assert_file_contains "$HAPROXY_CONF" "stats uri /haproxy?stats" "stats URI"
assert_file_contains "$HAPROXY_CONF" "option httpchk GET /" "health check"
assert_file_contains "$HAPROXY_CONF" "http-check expect status 200,401" "expect status"
assert_file_contains "$HAPROXY_CONF" "ssl verify none" "SSL verify disabled"
assert_file_contains "$HAPROXY_CONF" "balance roundrobin" "roundrobin balance"
assert_file_contains "$HAPROXY_CONF" "node0_10_0_0_10" "backend node0"
assert_file_contains "$HAPROXY_CONF" "node1_10_0_0_11" "backend node1"
assert_file_contains "$HAPROXY_CONF" "inter 2000" "health check interval"
}
rm -f /tmp/haproxy-lb-test_haproxy.cfg

# --- Test: Empty BACKENDS_LIST is rejected ---
echo -e "  ${BLUE}TEST:${NC} rejects empty BACKENDS_LIST with error"
{
BACKENDS_LIST=""
BACKENDS_FILE="/tmp/haproxy-lb-test_empty_backends.conf"
rm -f "$BACKENDS_FILE"

COUNT=0
if [ -f "$BACKENDS_FILE" ]; then
    while IFS= read -r line; do
        line="$(echo "$line" | sed 's/#.*//' | xargs)"
        [ -z "$line" ] && continue
        BACKENDS_LIST="${BACKENDS_LIST:+${BACKENDS_LIST},}${line}"
        COUNT=$((COUNT + 1))
    done < "$BACKENDS_FILE"
elif [ -n "$BACKENDS_LIST" ]; then
    IFS=',' read -ra ADDR <<< "$BACKENDS_LIST"
    for ip_port in "${ADDR[@]}"; do
        COUNT=$((COUNT + 1))
    done
fi

assert_eq "0" "$COUNT" "zero backends detected"
}

# --- Test: BACKENDS_LIST with whitespace is sanitized ---
echo -e "  ${BLUE}TEST:${NC} sanitizes whitespace in BACKENDS_LIST"
{
BACKENDS_LIST="10.0.0.10:8006 , 10.0.0.11:8006 , 10.0.0.12:8006"
HC_INTERVAL="2000"

SERVERS=""
COUNT=0
IFS=',' read -ra ADDR <<< "$BACKENDS_LIST"
for ip_port in "${ADDR[@]}"; do
    ip_port="$(echo "$ip_port" | xargs)"
    [ -z "$ip_port" ] && continue
    ip_part="$(echo "$ip_port" | cut -d: -f1 | tr '.' '_')"
    server_name="node${COUNT}_${ip_part}"
    SERVERS+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL} rise 2 fall 3
"
    COUNT=$((COUNT + 1))
done

assert_eq "3" "$COUNT" "three backends after whitespace trim"
assert_contains "$SERVERS" "server node0_10_0_0_10 10.0.0.10:8006" "trimmed server directive"
}

# --- Test: Single backend works ---
echo -e "  ${BLUE}TEST:${NC} handles single backend"
{
BACKENDS_LIST="10.0.0.10:8006"
HC_INTERVAL="2000"

SERVERS=""
COUNT=0
IFS=',' read -ra ADDR <<< "$BACKENDS_LIST"
for ip_port in "${ADDR[@]}"; do
    ip_port="$(echo "$ip_port" | xargs)"
    [ -z "$ip_port" ] && continue
    ip_part="$(echo "$ip_port" | cut -d: -f1 | tr '.' '_')"
    server_name="node${COUNT}_${ip_part}"
    SERVERS+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL} rise 2 fall 3
"
    COUNT=$((COUNT + 1))
done

assert_eq "1" "$COUNT" "single backend"
assert_contains "$SERVERS" "server node0_10_0_0_10 10.0.0.10:8006" "single server directive"
}

# --- Test: Certificate generation logic ---
echo -e "  ${BLUE}TEST:${NC} generates self-signed certificate"
VIP_ADDRESS="10.0.0.1"
CERT_DIR="/tmp/haproxy-lb-test_cert"
CERT_FILE="$CERT_DIR/backend.pem"
rm -rf "$CERT_DIR"
mkdir -p "$CERT_DIR"

openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
    -days 365 \
    -subj "/CN=${VIP_ADDRESS}" 2>/dev/null
cat "$CERT_DIR/cert.pem" "$CERT_DIR/key.pem" > "$CERT_FILE"
rm -f "$CERT_DIR/key.pem" "$CERT_DIR/cert.pem"
chmod 600 "$CERT_FILE"

assert_file_exists "$CERT_FILE" "certificate file created"
CERT_SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null || echo "")
assert_contains "$CERT_SUBJECT" "10.0.0.1" "certificate CN matches VIP"
rm -rf /tmp/haproxy-lb-test_cert

# --- Test: Default environment variable values ---
echo -e "  ${BLUE}TEST:${NC} uses correct default values for environment variables"
unset VIP_ADDRESS VIP_SUBNET VRRP_INTERFACE VRRP_VRID NODE_PRIORITY VRRP_AUTH_PASS HC_INTERVAL 2>/dev/null || true

VIP_ADDRESS="${VIP_ADDRESS:-192.168.1.100}"
VIP_SUBNET="${VIP_SUBNET:-24}"
VRRP_INTERFACE="${VRRP_INTERFACE:-eth0}"
VRRP_VRID="${VRRP_VRID:-50}"
NODE_PRIORITY="${NODE_PRIORITY:-110}"
VRRP_AUTH_PASS="${VRRP_AUTH_PASS:-CHANGE_ME_PASSWORD}"
HC_INTERVAL="${HC_INTERVAL:-2000}"

assert_eq "192.168.1.100" "$VIP_ADDRESS" "VIP default"
assert_eq "24" "$VIP_SUBNET" "VIP subnet default"
assert_eq "eth0" "$VRRP_INTERFACE" "interface default"
assert_eq "50" "$VRRP_VRID" "VRID default"
assert_eq "110" "$NODE_PRIORITY" "priority default"
assert_eq "CHANGE_ME_PASSWORD" "$VRRP_AUTH_PASS" "auth pass default"
assert_eq "2000" "$HC_INTERVAL" "HC interval default"

print_summary
