#!/usr/bin/env bash
# =============================================================================
# Docker entrypoint — generates configs from env vars, starts keepalived + haproxy
# Usage:
#   docker run --network host --cap-add NET_ADMIN ... ha-lb
#   docker-compose up
# =============================================================================
set -euo pipefail

# --- Environment variables (with defaults) ---
VIP_ADDRESS="${VIP_ADDRESS:-192.168.1.100}"
VIP_SUBNET="${VIP_SUBNET:-24}"
VRRP_INTERFACE="${VRRP_INTERFACE:-eth0}"
VRRP_VRID="${VRRP_VRID:-50}"
NODE_PRIORITY="${NODE_PRIORITY:-110}"
NODE_IP="${NODE_IP:-}"
VRRP_AUTH_PASS="${VRRP_AUTH_PASS:-CHANGE_ME_PASSWORD}"

# HAProxy backends — from env var (comma-separated) or mounted file
BACKENDS_LIST="${BACKENDS_LIST:-}"
BACKENDS_FILE="/etc/haproxy-lb/backends.conf"

# Health check interval (ms)
HC_INTERVAL="${HC_INTERVAL:-2000}"

# Internal: determine initial VRRP state
INITIAL_STATE="MASTER"
if [ "$NODE_PRIORITY" -lt 100 ] 2>/dev/null; then
    INITIAL_STATE="BACKUP"
fi

# Internal: weight for HAProxy failure detection
HA_PROXY_WEIGHT=20

# Internal: derive router_id from interface name (replace dots with underscores)
ROUTER_ID="LBA_$(echo "$VRRP_INTERFACE" | tr '.' '_')"

# --- Resolve node IP (auto-detect if not set) ---
if [ -z "$NODE_IP" ]; then
    # Try to get the IP of the VRRP interface
    NODE_IP="$(ip -4 addr show "$VRRP_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "")"
    if [ -z "$NODE_IP" ]; then
        echo "WARNING: Could not auto-detect IP for interface ${VRRP_INTERFACE}"
        echo "         Set NODE_IP environment variable explicitly"
        echo "         Using VIP address as fallback"
        NODE_IP="$VIP_ADDRESS"
    else
        echo "Auto-detected NODE_IP=${NODE_IP} from ${VRRP_INTERFACE}"
    fi
else
    echo "NODE_IP=${NODE_IP} (from env)"
fi

# --- Load backends ---
# Priority: mounted file > env var
BACKEND_LINES=""
if [ -f "$BACKENDS_FILE" ]; then
    echo "Loading backends from ${BACKENDS_FILE}"
    # Parse the file — each line is IP:PORT, comments starting with # are ignored
    while IFS= read -r line; do
        # Skip comments and blank lines
        line="$(echo "$line" | sed 's/#.*//' | xargs)"
        [ -z "$line" ] && continue
        BACKENDS_LIST="${BACKENDS_LIST:+${BACKENDS_LIST},}${line}"
    done < "$BACKENDS_FILE"
elif [ -n "$BACKENDS_LIST" ]; then
    echo "Loading backends from BACKENDS_LIST env var"
else
    echo "ERROR: No backends configured!" >&2
    echo "  Set BACKENDS_LIST=ip:port,ip:port,... or mount a config file to ${BACKENDS_FILE}" >&2
    exit 1
fi

# Build HAProxy backend server directives
SERVERS=""
COUNT=0
IFS=',' read -ra ADDR <<< "$BACKENDS_LIST"
for ip_port in "${ADDR[@]}"; do
    # Sanitize: strip whitespace
    ip_port="$(echo "$ip_port" | xargs)"
    [ -z "$ip_port" ] && continue

    # Generate server name from IP (replace dots with underscores)
    ip_part="$(echo "$ip_port" | cut -d: -f1 | tr '.' '_')"
    server_name="node${COUNT}_${ip_part}"

    SERVERS+="    server ${server_name} ${ip_port} check inter ${HC_INTERVAL} rise 2 fall 3
"
    COUNT=$((COUNT + 1))
done

if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: No valid backends found!" >&2
    exit 1
fi

echo "Configured with ${COUNT} backend(s): ${BACKENDS_LIST}"

# --- Certificates ---
# Let's Encrypt: mount the host's certbot dir read-only at /etc/letsencrypt and
# set LETSENCRYPT_DOMAINS to the certbot live-dir name(s) (comma-separated).
# HAProxy needs cert+key in one file, so each domain's fullchain.pem+privkey.pem
# is (re)combined into /etc/haproxy/certs/<domain>.pem on every start — this
# picks up renewals automatically on container restart. A single wildcard cert
# (e.g. live dir "example.com" for a *.example.com cert) covers every subdomain,
# so no per-domain cert/SNI matching is needed — just reference that one file.
LETSENCRYPT_DIR="${LETSENCRYPT_DIR:-/etc/letsencrypt}"
LETSENCRYPT_DOMAINS="${LETSENCRYPT_DOMAINS:-}"

mkdir -p /etc/haproxy/certs
CERT_FILE="/etc/haproxy/certs/backend.pem"

if [ -n "$LETSENCRYPT_DOMAINS" ]; then
    FIRST_DOMAIN=""
    IFS=',' read -ra LE_DOMAINS <<< "$LETSENCRYPT_DOMAINS"
    for domain in "${LE_DOMAINS[@]}"; do
        domain="$(echo "$domain" | xargs)"
        [ -z "$domain" ] && continue
        [ -z "$FIRST_DOMAIN" ] && FIRST_DOMAIN="$domain"

        LIVE_DIR="${LETSENCRYPT_DIR}/live/${domain}"
        if [ -f "${LIVE_DIR}/fullchain.pem" ] && [ -f "${LIVE_DIR}/privkey.pem" ]; then
            cat "${LIVE_DIR}/fullchain.pem" "${LIVE_DIR}/privkey.pem" > "/etc/haproxy/certs/${domain}.pem"
            chmod 600 "/etc/haproxy/certs/${domain}.pem"
            echo "Combined Let's Encrypt cert for ${domain} -> /etc/haproxy/certs/${domain}.pem"
        else
            echo "WARNING: No Let's Encrypt cert found at ${LIVE_DIR} (expected fullchain.pem + privkey.pem)" >&2
        fi
    done
    CERT_FILE="/etc/haproxy/certs/${FIRST_DOMAIN}.pem"
fi

if [ ! -f "$CERT_FILE" ]; then
    echo "Generating self-signed certificate for HAProxy frontend..."
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout /tmp/haproxy-key.pem -out /tmp/haproxy-cert.pem \
        -days 365 \
        -subj "/CN=${VIP_ADDRESS}" 2>/dev/null
    cat /tmp/haproxy-cert.pem /tmp/haproxy-key.pem > "$CERT_FILE"
    rm -f /tmp/haproxy-key.pem /tmp/haproxy-cert.pem
    chmod 600 "$CERT_FILE"
else
    echo "Using certificate: ${CERT_FILE}"
fi

# --- Generate keepalived.conf ---
echo "Generating /etc/keepalived/keepalived.conf ..."
cat > /etc/keepalived/keepalived.conf << EOF
global_defs {
    router_id ${ROUTER_ID}
    notification_email_from keepalived@localhost
    smtp_server 127.0.0.1
    smtp_connect_timeout 30
}

vrrp_nosync

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
EOF

chmod 600 /etc/keepalived/keepalived.conf

# --- Generate haproxy.cfg ---
# If a custom config is bind-mounted read-only at this path (e.g. for SNI
# multi-vhost setups), skip generation and use it as-is.
if [ -e /etc/haproxy/haproxy.cfg ] && [ ! -w /etc/haproxy/haproxy.cfg ]; then
    echo "Using custom mounted /etc/haproxy/haproxy.cfg (read-only) — skipping generation"
else

echo "Generating /etc/haproxy/haproxy.cfg ..."
cat > /etc/haproxy/haproxy.cfg << EOF
global
    log stdout format raw local0
    log stdout format raw local1 notice
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

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
    timeout http-request 10s
    timeout http-keep-alive 10s

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy?stats
    stats refresh 10s
    stats admin if LOCALHOST

frontend backend_https
    bind *:443 ssl crt ${CERT_FILE}
    default_backend backend_nodes

frontend backend_http
    bind *:80
    http-request redirect scheme https code 301

backend backend_nodes
    balance roundrobin
    option httpchk GET /
    http-check expect status 200,401
    default-server ssl verify none

${SERVERS}
EOF

chmod 644 /etc/haproxy/haproxy.cfg

fi

echo ""
echo "=== Configuration generated ==="
echo "  VIP:             ${VIP_ADDRESS}/${VIP_SUBNET} on ${VRRP_INTERFACE}"
echo "  VRRP:            state=${INITIAL_STATE} priority=${NODE_PRIORITY} VRID=${VRRP_VRID}"
echo "  Backends:        ${COUNT} node(s)"
echo "  Frontend:        https://*:443"
echo "  HTTP redirect:   *:80"
echo "  Stats:           http://*:8404/haproxy?stats"
echo ""

# --- Parse arguments ---
# Check if --foreground was passed (for CMD in Dockerfile)
# If no args, default to --foreground
if [ "${1:-}" != "--foreground" ] && [ $# -gt 0 ]; then
    exec "$@"
fi

# --- Start services in foreground ---
# Run keepalived in foreground (foreground mode)
# HAProxy runs as daemon (it forks), keepalived holds the container open

echo "Starting HAProxy..."
haproxy -f /etc/haproxy/haproxy.cfg -D

echo "Starting Keepalived (foreground)..."
exec keepalived -f /etc/keepalived/keepalived.conf -n --log-console
