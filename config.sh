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

# --- HAProxy backends (the Proxmox nodes) ---
# List ALL Proxmox nodes here — HAProxy health-checks each one
# Format: IP:PORT
BACKENDS=(
    "192.168.1.10:8006"
    "192.168.1.11:8006"
    "192.168.1.12:8006"
)

# Health check settings
HC_INTERVAL=2000         # Check interval in ms (HAProxy)
HC_TIMEOUT=5000          # Check timeout in ms
HC_HTTP_VERSION="1.1"    # HTTP version for health checks

# --- Proxmox-specific ---
# Proxmox uses self-signed certs. HAProxy needs to accept that.
PROXMOX_USER="_proxy"    # Optional: a dedicated read-only user on ALL Proxmox nodes
                         # Leave empty for no auth (not recommended for production)
# If using auth, create this user on every node:
#   pum user add ${PROXMOX_USER} --role Admin --comment "HAProxy health check"

# --- Optional: SMTP for alerts ---
# SMTP_SERVER="127.0.0.1"
# ALERT_EMAIL="admin@example.com"
