#!/usr/bin/env bash
# =============================================================================
# Install and configure dependencies on ALL nodes
# Run once per node (as root or with sudo)
# =============================================================================
set -euo pipefail

echo "=== Installing HA Load Balancer dependencies ==="

# --- Packages ---
echo "[1/4] Installing packages ..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    keepalived \
    haproxy \
    socat \
    openssl \
    iproute2 \
    psmisc

# --- Enable IP forwarding (needed for VIP assignment) ---
echo "[2/4] Configuring kernel parameters ..."
cat > /etc/sysctl.d/99-ha-lb.conf << 'SYSCTL'
# Allow multiple processes to bind to the same VIP interface address
net.ipv4.ip_nonlocal_bind = 1
# Accept VRRP multicast packets
net.ipv4.vrrp_mcast_group4 = 224.0.0.18
SYSCTL
sysctl -p /etc/sysctl.d/99-ha-lb.conf 2>/dev/null || true

# --- Keepalived: allow non-local VIP binding ---
echo "[3/4] Configuring keepalived ..."
# Some distros need this to allow the VIP to bind without a matching RT entry
mkdir -p /etc/keepalived
if ! grep -q "^vrrp_ipsc" /etc/keepalived/keepalived.conf 2>/dev/null; then
    echo "# Allow VIP to bind even if not yet routed" >> /etc/keepalived/keepalived.conf 2>/dev/null || true
fi

# --- HAProxy: enable in config ---
echo "[4/4] Enabling HAProxy ..."
sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/haproxy 2>/dev/null || \
    echo 'ENABLED=1' >> /etc/default/haproxy 2>/dev/null || true

echo ""
echo "=== Dependencies installed ==="
echo ""
echo "Now deploy your configs and run: deploy.sh"
