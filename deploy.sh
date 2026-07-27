#!/usr/bin/env bash
# =============================================================================
# Deploy script — generates final configs from templates + node config
# Run on EACH node after copying config.sh and the node-specific node.conf
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load configuration ---
if [[ ! -f "${SCRIPT_DIR}/config.sh" ]]; then
    echo "ERROR: ${SCRIPT_DIR}/config.sh not found" >&2
    exit 1
fi
source "${SCRIPT_DIR}/config.sh"

NODE_CONF="/etc/haproxy-lb/node.conf"
if [[ ! -f "$NODE_CONF" ]]; then
    echo "ERROR: ${NODE_CONF} not found — deploy this per-node config to each node" >&2
    echo "Template: ${SCRIPT_DIR}/node.conf.template" >&2
    exit 1
fi
source "$NODE_CONF"

# --- Defaults ---
HA_PROXY_WEIGHT=20
INITIAL_STATE="MASTER"
if [[ $NODE_PRIORITY -lt 100 ]]; then
    INITIAL_STATE="BACKUP"
fi

echo "=== HA Load Balancer Deployment ==="
echo "Node priority:  ${NODE_PRIORITY}"
echo "VIP:            ${VIP_ADDRESS}/${VIP_SUBNET}"
echo "Interface:      ${VRRP_INTERFACE}"
echo "HAProxy mode:   ${INITIAL_STATE}"
echo "Backends:       ${#BACKENDS[@]} nodes"
echo ""

# --- Build backend directives for HAProxy ---
BACKEND_LINES=""
BACKEND_STICKY_LINES=""
for i in "${!BACKENDS[@]}"; do
    ip_port="${BACKENDS[$i]}"
    # Generate a unique server name from the IP
    server_name="node${i}.$(echo "$ip_port" | cut -d: -f1 | tr '.' '_')"
    BACKEND_LINES+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL}m fall 3 rise 2\n"
    BACKEND_STICKY_LINES+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL}m fall 3 rise 2 cookie node${i}\n"
done

# --- Generate keepalived.conf ---
echo "[1/3] Generating /etc/keepalived/keepalived.conf ..."
mkdir -p /etc/keepalived

sed -e "s/\${VRRP_INTERFACE}/${VRRP_INTERFACE}/g" \
    -e "s/\${VRRP_VRID}/${VRRP_VRID}/g" \
    -e "s/\${VIP_ADDRESS}/${VIP_ADDRESS}/g" \
    -e "s/\${VIP_SUBNET}/${VIP_SUBNET}/g" \
    -e "s/\${NODE_PRIORITY}/${NODE_PRIORITY}/g" \
    -e "s/\${NODE_IP}/${NODE_IP}/g" \
    -e "s/\${HA_PROXY_WEIGHT}/${HA_PROXY_WEIGHT}/g" \
    -e "s/\${INITIAL_STATE}/${INITIAL_STATE}/g" \
    "${SCRIPT_DIR}/keepalived.conf.template" \
    > /etc/keepalived/keepalived.conf

chmod 600 /etc/keepalived/keepalived.conf

# --- Generate haproxy.cfg ---
echo "[2/3] Generating /etc/haproxy/haproxy.cfg ..."
mkdir -p /etc/haproxy/certs

sed -e "s/\${HC_INTERVAL}/${HC_INTERVAL}/g" \
    -e "s|\${BACKENDS_DIRECTIVE}|$(echo -e "$BACKEND_LINES")|g" \
    "${SCRIPT_DIR}/haproxy.cfg.template" \
    > /etc/haproxy/haproxy.cfg

chmod 644 /etc/haproxy/haproxy.cfg

# --- Self-signed cert for HAProxy (if backends use self-signed) ---
if [[ ! -f /etc/haproxy/certs/backend.pem ]]; then
    echo "  Creating self-signed cert bundle for HAProxy frontend ..."
    # Generate a cert that covers the VIP
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /tmp/haproxy-key.pem -out /tmp/haproxy-cert.pem \
        -days 365 -subj "/CN=${VIP_ADDRESS}" 2>/dev/null
    cat /tmp/haproxy-cert.pem /tmp/haproxy-key.pem > /etc/haproxy/certs/backend.pem
    rm -f /tmp/haproxy-key.pem /tmp/haproxy-cert.pem
    chmod 600 /etc/haproxy/certs/backend.pem
fi

# --- Install health check script ---
echo "[3/3] Installing health check script ..."
mkdir -p /usr/local/bin
cp "${SCRIPT_DIR}/ha-check-haproxy.sh" /usr/local/bin/ha-check-haproxy.sh
chmod 755 /usr/local/bin/ha-check-haproxy.sh

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Next steps:"
echo "  1. Copy config.sh and node.conf to ALL nodes"
echo "  2. Run this script on each node"
echo "  3. Install dependencies: apt install keepalived haproxy socat openssl"
echo "  4. Start services: systemctl enable --now keepalived haproxy"
echo "  5. Verify VIP: ip addr show ${VRRP_INTERFACE}"
echo "  6. Test: curl -k https://${VIP_ADDRESS}:8006"
