#!/usr/bin/env bash
# =============================================================================
# Tests for configuration templates — structure and variable markers
# =============================================================================
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

PROJECT_ROOT="$(dirname "$TEST_DIR")"

echo -e "${BLUE}═══ Testing templates — structure and variable markers ${NC}"

# --- Test: haproxy.cfg.template has required sections ---
echo -e "  ${BLUE}TEST:${NC} haproxy.cfg.template has all required sections"
{
TEMPLATE="$PROJECT_ROOT/haproxy.cfg.template"
CONTENT=$(cat "$TEMPLATE")

assert_contains "$CONTENT" "global" "global section"
assert_contains "$CONTENT" "defaults" "defaults section"
assert_contains "$CONTENT" "frontend backend_https" "HTTPS frontend"
assert_contains "$CONTENT" "frontend backend_http" "HTTP frontend"
assert_contains "$CONTENT" "backend backend_nodes" "backend section"
assert_contains "$CONTENT" "listen stats" "stats listener"
assert_contains "$CONTENT" "stats uri" "stats URI"
assert_contains "$CONTENT" "option httpchk" "HTTP health check option"
assert_contains "$CONTENT" "option httpchk GET /" "HTTP health check path"
}

# --- Test: keepalived.conf.template has required sections ---
echo -e "  ${BLUE}TEST:${NC} keepalived.conf.template has all required sections"
{
TEMPLATE="$PROJECT_ROOT/keepalived.conf.template"
CONTENT=$(cat "$TEMPLATE")

assert_contains "$CONTENT" "global_defs" "global_defs section"
assert_contains "$CONTENT" "router_id" "router_id"
assert_contains "$CONTENT" "vrrp_script chk_haproxy" "chk_haproxy vrrp_script"
assert_contains "$CONTENT" "interval 2" "check interval"
assert_contains "$CONTENT" "vrrp_instance VIP" "vrrp_instance section"
assert_contains "$CONTENT" "interface" "interface directive"
assert_contains "$CONTENT" "priority" "priority directive"
assert_contains "$CONTENT" "authentication" "authentication block"
assert_contains "$CONTENT" "auth_type PASS" "auth type"
assert_contains "$CONTENT" "virtual_ipaddress" "virtual_ipaddress"
assert_contains "$CONTENT" "track_script" "track_script"
assert_contains "$CONTENT" "advert_int 1" "advertise interval"
}

# --- Test: keepalived.conf.template uses correct variable markers ---
echo -e "  ${BLUE}TEST:${NC} keepalived.conf.template uses deploy.sh variable markers"
{
TEMPLATE="$PROJECT_ROOT/keepalived.conf.template"
CONTENT=$(cat "$TEMPLATE")

REQUIRED_VARS=(
    "VRRP_INTERFACE"
    "VRRP_VRID"
    "VIP_ADDRESS"
    "VIP_SUBNET"
    "NODE_PRIORITY"
    "NODE_IP"
    "HA_PROXY_WEIGHT"
    "INITIAL_STATE"
)

for var in "${REQUIRED_VARS[@]}"; do
    marker="\${${var}}"
    if echo "$CONTENT" | grep -qF "$marker"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC} — variable $marker present"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC} — variable $marker MISSING"
    fi
done
}

# --- Test: haproxy.cfg.template uses correct variable markers ---
echo -e "  ${BLUE}TEST:${NC} haproxy.cfg.template uses deploy.sh variable markers"
{
TEMPLATE="$PROJECT_ROOT/haproxy.cfg.template"
CONTENT=$(cat "$TEMPLATE")

assert_contains "$CONTENT" '${HC_INTERVAL}' "HC_INTERVAL marker"
assert_contains "$CONTENT" '${BACKENDS_DIRECTIVE}' "BACKENDS_DIRECTIVE marker"
}

# --- Test: Templates reference correct file paths ---
echo -e "  ${BLUE}TEST:${NC} templates reference correct file paths"
{
# keepalived template references the check script
KAL="$PROJECT_ROOT/keepalived.conf.template"
KAL_CONTENT=$(cat "$KAL")
assert_contains "$KAL_CONTENT" "/usr/local/bin/ha-check-haproxy.sh" "check script path in keepalived"

# HAProxy template references the cert
HAP="$PROJECT_ROOT/haproxy.cfg.template"
HAP_CONTENT=$(cat "$HAP")
assert_contains "$HAP_CONTENT" "/etc/haproxy/certs/backend.pem" "cert path in haproxy"
}

# --- Test: docker-compose.yml has required keys ---
echo -e "  ${BLUE}TEST:${NC} docker-compose.yml has required keys"
{
COMPOSE="$PROJECT_ROOT/docker-compose.yml"
CONTENT=$(cat "$COMPOSE")

assert_contains "$CONTENT" "services:" "services block"
assert_contains "$CONTENT" "network_mode: host" "host network mode"
assert_contains "$CONTENT" "privileged: true" "privileged mode"
assert_contains "$CONTENT" "restart: unless-stopped" "restart policy"
assert_contains "$CONTENT" "VIP_ADDRESS" "VIP_ADDRESS env var"
assert_contains "$CONTENT" "VRRP_INTERFACE" "VRRP_INTERFACE env var"
assert_contains "$CONTENT" "BACKENDS_LIST" "BACKENDS_LIST env var"
assert_contains "$CONTENT" "healthcheck:" "healthcheck config"
assert_contains "$CONTENT" "net.ipv4.ip_nonlocal_bind" "sysctl setting"
}

# --- Test: backends.conf.sample has correct format ---
echo -e "  ${BLUE}TEST:${NC} backends.conf.sample has correct format"
{
SAMPLE="$PROJECT_ROOT/samples/backends.conf.sample"
CONTENT=$(cat "$SAMPLE")

BACKEND_COUNT=$(grep -v '^#' "$SAMPLE" | grep -v '^$' | grep -c ':' || echo "0")
assert_eq "3" "$BACKEND_COUNT" "three backend entries"

while IFS= read -r line; do
    [[ "$line" =~ ^# ]] && continue
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC} — valid backend: $line"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}FAIL${NC} — invalid backend: $line"
    fi
done < "$SAMPLE"
}

# --- Test: node.conf.template has required variables ---
echo -e "  ${BLUE}TEST:${NC} node.conf.template has required variables"
{
TEMPLATE="$PROJECT_ROOT/node.conf.template"
CONTENT=$(cat "$TEMPLATE")

assert_contains "$CONTENT" "NODE_PRIORITY" "NODE_PRIORITY variable"
assert_contains "$CONTENT" "NODE_IP" "NODE_IP variable"
DEFAULT_PRIORITY=$(grep '^NODE_PRIORITY' "$TEMPLATE" | cut -d= -f2 | tr -d ' "')
assert_eq "110" "$DEFAULT_PRIORITY" "default priority 110"
}

# --- Test: Dockerfile has correct base and instructions ---
echo -e "  ${BLUE}TEST:${NC} Dockerfile has correct base image and instructions"
{
DOCKERFILE="$PROJECT_ROOT/Dockerfile"
CONTENT=$(cat "$DOCKERFILE")

assert_contains "$CONTENT" "FROM alpine" "alpine base image"
assert_contains "$CONTENT" "keepalived" "keepalived package"
assert_contains "$CONTENT" "haproxy" "haproxy package"
assert_contains "$CONTENT" "socat" "socat package"
assert_contains "$CONTENT" "openssl" "openssl package"
assert_contains "$CONTENT" "COPY entrypoint.sh" "entrypoint copy"
assert_contains "$CONTENT" "COPY ha-check-haproxy.sh" "check script copy"
assert_contains "$CONTENT" "ENTRYPOINT" "entrypoint instruction"
assert_contains "$CONTENT" "CMD" "cmd instruction"
assert_contains "$CONTENT" "EXPOSE 8006" "port 8006 exposed"
assert_contains "$CONTENT" "8404" "port 8404 exposed"
}

# --- Test: entrypoint.sh has correct structure ---
echo -e "  ${BLUE}TEST:${NC} entrypoint.sh has correct structure"
{
SCRIPT="$PROJECT_ROOT/entrypoint.sh"
CONTENT=$(cat "$SCRIPT")

assert_contains "$CONTENT" "set -euo pipefail" "strict mode"
assert_contains "$CONTENT" "VIP_ADDRESS" "VIP_ADDRESS env var"
assert_contains "$CONTENT" "VRRP_INTERFACE" "VRRP_INTERFACE env var"
assert_contains "$CONTENT" "BACKENDS_LIST" "BACKENDS_LIST env var"
assert_contains "$CONTENT" "NODE_PRIORITY" "NODE_PRIORITY env var"
assert_contains "$CONTENT" "openssl" "openssl for cert"
assert_contains "$CONTENT" "keepalived" "keepalived start"
assert_contains "$CONTENT" "haproxy" "haproxy start"
assert_contains "$CONTENT" "/etc/keepalived/keepalived.conf" "keepalived conf path"
assert_contains "$CONTENT" "/etc/haproxy/haproxy.cfg" "haproxy conf path"
}

print_summary
