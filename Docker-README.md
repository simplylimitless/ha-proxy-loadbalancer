# HA Load Balancer — Docker Deployment

Run the floating VIP + load balancer as a Docker container on Raspberry Pi (or any ARM64/x86_64 Linux host).

## Architecture

```
                  DNS: proxmox.example.com
                         ↓
                    Floating VIP (192.168.1.100)
                         ↓
              Container on VIP-owner Pi
              ┌──────────────────────────────┐
              │  keepalived  → VRRP heartbeat │
              │  haproxy     → load balance   │
              │  health check  → VIP failover  │
              └──────────────────────────────┘
                         ↓
              Proxmox Node 1 (:8006)  ◄── healthy
              Proxmox Node 2 (:8006)  ◄── healthy
              Proxmox Node 3 (:8006)  ◄── healthy
```

**Why `network_mode: host`?**
Keepalived must bind the VIP to the host's network interface. Docker's default bridge network doesn't support this — host mode gives the container direct access to the host's network stack.

## Prerequisites

- Raspberry Pi OS (or any Linux distro) with Docker installed
- ARM64 (aarch64) or amd64
- One unused IP address on your LAN for the VIP (or reuse an existing one)
- All 3 Proxmox nodes on the same subnet/LAN

## Pull the Image

```bash
# Pull the pre-built multi-arch image (ARM64 or amd64)
docker pull ghcr.io/simplylimitless/ha-proxy-loadbalancer:latest
```

**or build locally:**

```bash
# Build for your current architecture (ARM64 on Raspberry Pi)
docker build -t ha-lb:latest .

# If cross-compiling from x86_64 to ARM64:
docker buildx build --platform linux/arm64 -t ha-lb:latest .
```

## Option 1: Docker Compose (Recommended)

### Step 1: Edit `docker-compose.yml`

Modify the environment variables for your network:

```yaml
environment:
  VIP_ADDRESS: 192.168.1.100  # Your floating IP
  VRRP_INTERFACE: eth0        # Your LAN interface (check: ip -br addr)
  VRRP_VRID: "50"             # Unique on your network (0-255)
  VRRP_AUTH_PASS: my-secret    # Change this!
  BACKENDS_LIST: >-
    192.168.1.10:8006,        # Proxmox node 1
    192.168.1.11:8006,        # Proxmox node 2
    192.168.1.12:8006         # Proxmox node 3
```

### Step 2: Deploy to each Pi

Pull the image first (one-time):

```bash
docker pull ghcr.io/simplylimitless/ha-proxy-loadbalancer:latest
```

On each Raspberry Pi, create a node-specific compose file:

```bash
# Pi 1 — primary VIP owner (priority 110)
VIP_ADDRESS=192.168.1.100 \
VRRP_INTERFACE=eth0 \
VRRP_VRID=50 \
NODE_PRIORITY=110 \
NODE_IP=192.168.1.10 \
BACKENDS_LIST="192.168.1.10:8006,192.168.1.11:8006,192.168.1.12:8006" \
VRRP_AUTH_PASS=my-secret \
docker compose up -d
```

```bash
# Pi 2 — backup (priority 90)
VIP_ADDRESS=192.168.1.100 \
VRRP_INTERFACE=eth0 \
VRRP_VRID=50 \
NODE_PRIORITY=90 \
NODE_IP=192.168.1.11 \
BACKENDS_LIST="192.168.1.10:8006,192.168.1.11:8006,192.168.1.12:8006" \
VRRP_AUTH_PASS=my-secret \
docker compose up -d
```

```bash
# Pi 3 — backup (priority 90)
VIP_ADDRESS=192.168.1.100 \
VRRP_INTERFACE=eth0 \
VRRP_VRID=50 \
NODE_PRIORITY=90 \
NODE_IP=192.168.1.12 \
BACKENDS_LIST="192.168.1.10:8006,192.168.1.11:8006,192.168.1.12:8006" \
VRRP_AUTH_PASS=my-secret \
docker compose up -d
```

### Alternative: Separate compose files per node

Create `docker-compose.pi1.yml`, `docker-compose.pi2.yml`, `docker-compose.pi3.yml` with different `NODE_PRIORITY` values, then run:

```bash
docker compose -f docker-compose.pi1.yml up -d
docker compose -f docker-compose.pi2.yml up -d
docker compose -f docker-compose.pi3.yml up -d
```

### Alternative: Mounted backends file

Instead of `BACKENDS_LIST`, mount a config file:

```yaml
volumes:
  - ./backends.conf:/etc/haproxy-lb/backends.conf:ro
```

Then create `backends.conf`:

```
192.168.1.10:8006
192.168.1.11:8006
192.168.1.12:8006
```

The mounted file takes precedence over the env var.

## Option 2: Docker Run (Single Command)

```bash
docker run -d \
  --name ha-lb \
  --network host \
  --privileged \
  --restart unless-stopped \
  -e VIP_ADDRESS=192.168.1.100 \
  -e VRRP_INTERFACE=eth0 \
  -e VRRP_VRID=50 \
  -e NODE_PRIORITY=110 \
  -e NODE_IP=192.168.1.10 \
  -e BACKENDS_LIST="192.168.1.10:8006,192.168.1.11:8006,192.168.1.12:8006" \
  -e VRRP_AUTH_PASS=my-secret \
  -e HC_INTERVAL=2000 \
  ghcr.io/simplylimitless/ha-proxy-loadbalancer:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VIP_ADDRESS` | `192.168.1.100` | The floating VIP (DNS points here) |
| `VIP_SUBNET` | `24` | CIDR subnet mask for the VIP |
| `VRRP_INTERFACE` | `eth0` | LAN interface name (find with: `ip -br addr`) |
| `VRRP_VRID` | `50` | VRRP router ID (unique per group on your network, 0-255) |
| `VRRP_AUTH_PASS` | `CHANGE_ME_PASSWORD` | VRRP authentication password |
| `NODE_PRIORITY` | `110` | VRRP priority (higher wins; primary=110, backups=90) |
| `NODE_IP` | *(auto-detected)* | This node's IP on the VRRP interface |
| `BACKENDS_LIST` | — | Comma-separated backends: `ip:port,ip:port,ip:port` |
| `HC_INTERVAL` | `2000` | HAProxy health check interval in milliseconds |

## Mounted Files

| Mount Path | Purpose | Example |
|------------|---------|---------|
| `/etc/haproxy-lb/backends.conf` | Backend server list (file overrides env var) | See `samples/backends.conf.sample` |
| `/etc/haproxy/certs/proxmox.pem` | TLS certificate (auto-generated if missing) | Custom cert for production |

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| `8006` | HTTPS | Proxmox VIP frontend (TLS terminated) |
| `8007` | HTTP | HTTP → HTTPS redirect |
| `8404` | HTTP | HAProxy stats page |

## Verify It Works

```bash
# Check which Pi holds the VIP (should be priority=110 node):
docker exec ha-lb ip addr show eth0 | grep "inet 192.168.1.100"

# Check container logs:
docker logs ha-lb

# Check HAProxy stats (on any Pi, port 8404):
curl -s http://192.168.1.10:8404/haproxy?stats | grep proxmox

# Test the floating VIP:
curl -k https://192.168.1.100:8006/api2/json

# Check all container status:
docker ps --filter "name=ha-lb"
```

## Failover Testing

```bash
# Stop the container on the VIP owner — VIP should float to backup
docker stop ha-lb
# Wait ~4 seconds, then verify VIP moved:
docker exec ha-lb-backup ip addr show eth0 | grep "inet 192.168.1.100"

# Restore the original:
docker start ha-lb
# VIP should return (preempt mode with priority 110)
```

## Troubleshooting

### VIP not appearing

```bash
# Check container logs for errors:
docker logs ha-lb --tail 50

# Verify the sysctl is set (needed for VIP binding):
docker exec ha-lb sysctl net.ipv4.ip_nonlocal_bind
# Should return: net.ipv4.ip_nonlocal_bind = 1

# Manually check if VIP can be assigned:
docker exec ha-lb ip addr add 192.168.1.100/24 dev eth0
# If this fails: wrong interface name or IP already in use

# Remove it:
docker exec ha-lb ip addr del 192.168.1.100/24 dev eth0
```

### Container won't start

```bash
# Check if network mode is supported:
docker run --network host --rm alpine ip -br addr
# Should show your interfaces

# Check capabilities:
docker run --rm --privileged alpine cat /proc/self/status | grep Cap

# Validate the image:
docker image inspect ha-lb:latest | grep -A5 "Architecture"
```

### VIP flapping (frequent failover)

- Ensure all 3 Pis are on the **same subnet** — VRRP multicast won't cross routers
- Check for network issues (bad cable, Wi-Fi, switch port errors)
- Verify `VRRP_VRID` is unique — conflicts cause chaos
- Ensure `VRRP_AUTH_PASS` matches on all nodes
- Check keepalived logs: `docker logs ha-lb | grep -i vrrp`

### HAProxy shows all backends down

```bash
# Test connectivity from the VIP-owner Pi:
docker exec ha-lb curl -kv https://192.168.1.10:8006/api2/json

# Check HAProxy logs:
docker logs ha-lb | grep -i backend

# Verify backends config:
docker exec ha-lb cat /etc/haproxy/haproxy.cfg
```

### Interface name is different

Find your interface name:

```bash
ip -br addr
# Output example:
# lo               UNKNOWN
# eth0             UP  192.168.1.10/24
# docker0          DOWN
```

Set the correct name: `-e VRRP_INTERFACE=eth0` (or `ens3`, `eno1`, etc.)

### Running on x86_64 (not Raspberry Pi)

Same setup works. The Dockerfile supports both `linux/arm64` and `linux/amd64`:

```bash
# Build for local architecture:
docker build -t ha-lb:latest .

# Cross-compile for Raspberry Pi from x86_64:
docker buildx build --platform linux/arm64 -t ha-lb:latest .
docker save ha-lb:latest | gzip > ha-lb-arm64.tar.gz
# Transfer to Pi and:
docker load < ha-lb-arm64.tar.gz
```

## Security

1. **Change `VRRP_AUTH_PASS`** — default `CHANGE_ME_PASSWORD` must be updated
2. **Restrict the stats page** — add to docker-compose:
   ```yaml
   environment:
     - STATS_AUTH=admin:your-secure-password
   ```
3. **Use a firewall** — restrict VRRP multicast (protocol 112) to trusted Pis:
   ```bash
   iptables -A INPUT -p vrrp -s 192.168.1.0/24 -j ACCEPT
   iptables -A INPUT -p vrrp -j DROP
   ```
4. **Replace the self-signed cert** — mount your own:
   ```yaml
   volumes:
     - ./certs/proxmox.pem:/etc/haproxy/certs/proxmox.pem:ro
   ```

## Cleanup

```bash
# Stop and remove all containers:
docker compose down

# Remove volumes and images:
docker compose down -v --rmi local
```
