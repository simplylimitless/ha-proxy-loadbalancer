#!/usr/bin/env bash
# =============================================================================
# Shared configuration — copy this file identically to ALL nodes
# Edit the values below, then deploy to each node.
# =============================================================================

# --- Network ---
# The floating VIP that clients/DNS point to
VIP_ADDRESS="192.168.1.100"
VIP_SUBNET="24"          # CIDR mask for the VIP (e.g., /24)

# VRRP settings
VRRP_INTERFACE="eth0"    # The network interface that holds the VIP
VRRP_VRID=50             # Virtual Router ID (0-255; must be unique per VRRP group on your network)
VRRP_MULTICAST_SRC="192.168.1.1"  # Source IP for VRRP multicast (usually the node's own IP on this interface)

# --- Backend servers ---
# List ALL backend nodes here — HAProxy health-checks each one
# Format: IP:PORT
BACKENDS=(
    "192.168.1.10:80"
    "192.168.1.11:80"
    "192.168.1.12:80"
)

# Health check settings
HC_INTERVAL=2000         # Check interval in ms (HAProxy)
HC_TIMEOUT=5000          # Check timeout in ms
HC_HTTP_VERSION="1.1"    # HTTP version for health checks

# --- Backend auth (optional) ---
# Some backends require auth for their API. Leave empty for no auth.
BACKEND_USER=""          # Optional: dedicated read-only user on all backend nodes

# --- Optional: SMTP for alerts ---
# SMTP_SERVER="127.0.0.1"
# ALERT_EMAIL="admin@example.com"
