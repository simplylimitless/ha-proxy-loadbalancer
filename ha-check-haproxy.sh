#!/usr/bin/env bash
# =============================================================================
# HAProxy health check for keepalived (Docker-optimized)
# Called by: vrrp_script chk_haproxy in keepalived.conf
# Exit 0 = HAProxy healthy
# Exit 1 = HAProxy down (triggers VIP failover)
# =============================================================================
set -euo pipefail

# Check if HAProxy is running
if ! pgrep -x haproxy > /dev/null 2>&1; then
    logger -t ha-check-haproxy "HAProxy not running"
    exit 1
fi

# Check if HAProxy socket is responsive
SOCKET="/run/haproxy/admin.sock"
if [ -S "$SOCKET" ]; then
    if echo "show info" | socat unix-connect:"$SOCKET" stdio 2>/dev/null | grep -q "Uptime"; then
        exit 0
    fi
fi

# Fallback: check if HAProxy is listening
if ss -tln | grep -q ":8006 "; then
    exit 0
fi

logger -t ha-check-haproxy "HAProxy not accepting connections"
exit 1
