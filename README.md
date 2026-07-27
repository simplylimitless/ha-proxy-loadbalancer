# HA Load Balancer

A floating VIP + load-balanced proxy for high-availability access to any service running on multiple nodes.

## Quick Start

```bash
# Pull the pre-built multi-arch image
docker pull ghcr.io/simplylimitless/ha-proxy-loadbalancer:latest

# Or build locally:
docker build -t ha-lb:latest .
```

### Docker Compose (Recommended)

Edit `docker-compose.yml` with your network settings, then run on each node:

```bash
# Node 1 — primary VIP owner (priority 110)
VIP_ADDRESS=192.168.1.100 VRRP_INTERFACE=eth0 VRRP_VRID=50 \
NODE_PRIORITY=110 NODE_IP=192.168.1.10 \
BACKENDS_LIST="192.168.1.10:80,192.168.1.11:80,192.168.1.12:80" \
VRRP_AUTH_PASS=my-secret docker compose up -d

# Node 2 — backup (priority 90)
VIP_ADDRESS=192.168.1.100 VRRP_INTERFACE=eth0 VRRP_VRID=50 \
NODE_PRIORITY=90 NODE_IP=192.168.1.11 \
BACKENDS_LIST="192.168.1.10:80,192.168.1.11:80,192.168.1.12:80" \
VRRP_AUTH_PASS=my-secret docker compose up -d

# Node 3 — backup (priority 90)
VIP_ADDRESS=192.168.1.100 VRRP_INTERFACE=eth0 VRRP_VRID=50 \
NODE_PRIORITY=90 NODE_IP=192.168.1.12 \
BACKENDS_LIST="192.168.1.10:80,192.168.1.11:80,192.168.1.12:80" \
VRRP_AUTH_PASS=my-secret docker compose up -d
```

### Docker Run (single command)

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
  -e BACKENDS_LIST="192.168.1.10:80,192.168.1.11:80,192.168.1.12:80" \
  -e VRRP_AUTH_PASS=my-secret \
  -e HC_INTERVAL=2000 \
  ghcr.io/simplylimitless/ha-proxy-loadbalancer:latest
```

## Architecture

```
                   DNS: example.com
                          ↓
                    Floating VIP (192.168.1.100)
                          ↓
              Container on VIP-owner node
              ┌──────────────────────────────┐
              │  keepalived  → VRRP heartbeat │
              │  haproxy     → load balance   │
              │  health check  → VIP failover  │
              └──────────────────────────────┘
                          ↓
              Backend 1 (:80)  ◄── healthy
              Backend 2 (:80)  ◄── healthy
              Backend 3 (:80)  ◄── healthy
```

### Two layers of failover

| Layer | Technology | What it protects against |
|-------|-----------|-------------------------|
| **Node failure** | Keepalived (VRRP) | VIP floats to another node if the owner dies |
| **Backend failure** | HAProxy health checks | Traffic routed around a dead backend |
| **Proxy failure** | `chk_haproxy` script | HAProxy crash triggers VIP failover via keepalived |

## Prerequisites

- Docker installed on each node (Raspberry Pi OS, Debian, Ubuntu, etc.)
- ARM64 (aarch64) or amd64
- One unused IP address on your LAN for the VIP (or reuse an existing one)
- All 3 backend nodes on the same subnet/LAN
- `network_mode: host` — required so keepalived can bind the VIP to the host's network interface
- `privileged` — needed for keepalived VIP binding

## How It Works

### Keepalived VRRP

- All 3 nodes run keepalived and advertise VRRP heartbeat every second
- The node with highest `NODE_PRIORITY` wins and owns the VIP
- If the owner stops advertising (crash, network partition), backups take over
- The `chk_haproxy` script lowers priority by 20 if HAProxy is dead
- Preempt mode (default): higher-priority node reclaims VIP when it recovers

### HAProxy Health Checks

- HAProxy sends an HTTP health check to each backend every 2 seconds (configurable interval via `HC_INTERVAL`)
- A backend is marked down after 3 consecutive failures (`fall 3`)
- A backend recovers after 2 consecutive successes (`rise 2`)
- SSL verification is disabled for self-signed certs

### HAProxy → Keepalived Integration

When HAProxy crashes:

1. `chk_haproxy.sh` detects the failure (process not running, socket unresponsive)
2. Keepalived lowers the node's VRRP priority by 20
3. A backup node (priority 90) takes the VIP
4. Services restart — normal operations resume on the new VIP owner

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VIP_ADDRESS` | `192.168.1.100` | The floating VIP (DNS points here) |
| `VIP_SUBNET` | `24` | CIDR subnet mask for the VIP |
| `VRRP_INTERFACE` | `eth0` | LAN interface name (find with: `ip -br addr`) |
| `VRRP_VRID` | `50` | VRRP router ID (unique per group on your network, 0–255) |
| `VRRP_AUTH_PASS` | `CHANGE_ME_PASSWORD` | VRRP authentication password |
| `NODE_PRIORITY` | `110` | VRRP priority (higher wins; primary=110, backups=90) |
| `NODE_IP` | *(auto-detected)* | This node's IP on the VRRP interface |
| `BACKENDS_LIST` | — | Comma-separated backends: `ip:port,ip:port,ip:port` |
| `HC_INTERVAL` | `2000` | HAProxy health check interval in milliseconds |

### Mounted Files

| Mount Path | Purpose | Example |
|------------|---------|---------|
| `/etc/haproxy-lb/backends.conf` | Backend server list (file overrides `BACKENDS_LIST` env var) | See `samples/backends.conf.sample` |
| `/etc/haproxy/certs/backend.pem` | TLS certificate (auto-generated if missing) | Mount your own as `./certs/backend.pem` |

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| `8006` | HTTPS | VIP frontend (TLS terminated) |
| `8007` | HTTP | HTTP → HTTPS redirect |
| `8404` | HTTP | HAProxy stats page |

### Backends File (Alternative to Env Var)

Instead of `BACKENDS_LIST`, mount a config file in `docker-compose.yml`:

```yaml
volumes:
  - ./backends.conf:/etc/haproxy-lb/backends.conf:ro
```

Create `backends.conf`:

```
192.168.1.10:80
192.168.1.11:80
192.168.1.12:80
```

The mounted file takes precedence over the env var.

## Verify It Works

```bash
# Check which node holds the VIP (should be priority=110 node):
docker exec ha-lb ip addr show eth0 | grep "inet 192.168.1.100"

# Check container logs:
docker logs ha-lb

# Check HAProxy stats (on any node, port 8404):
curl -s http://192.168.1.10:8404/haproxy?stats

# Test the floating VIP:
curl -k https://192.168.1.100:8006

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

# Validate the image architecture:
docker image inspect ghcr.io/simplylimitless/ha-proxy-loadbalancer:latest | grep -A5 "Architecture"
```

### VIP flapping (frequent failover)

- Ensure all 3 nodes are on the **same subnet** — VRRP multicast won't cross routers
- Check for network issues (bad cable, Wi-Fi, switch port errors)
- Verify `VRRP_VRID` is unique — conflicts cause chaos
- Ensure `VRRP_AUTH_PASS` matches on all nodes
- Check keepalived logs: `docker logs ha-lb | grep -i vrrp`

### HAProxy shows all backends down

```bash
# Test connectivity from the VIP-owner node:
docker exec ha-lb curl -kv https://192.168.1.10:80/

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

Same setup works. The image supports both `linux/arm64` and `linux/amd64`:

```bash
# Pull (multi-arch image auto-selects based on host):
docker pull ghcr.io/simplylimitless/ha-proxy-loadbalancer:latest

# Or build for a specific architecture from another machine:
docker buildx build --platform linux/arm64 -t ha-lb:latest .
docker save ha-lb:latest | gzip > ha-lb-arm64.tar.gz
# Transfer to Pi and:
docker load < ha-lb-arm64.tar.gz
```

## Security

1. **Change `VRRP_AUTH_PASS`** — default `CHANGE_ME_PASSWORD` must be updated
2. **Restrict the stats page** — add to `docker-compose.yml`:
   ```yaml
   environment:
     - STATS_AUTH=admin:your-secure-password
   ```
3. **Use a firewall** — restrict VRRP multicast (protocol 112) to trusted nodes:
   ```bash
   iptables -A INPUT -p vrrp -s 192.168.1.0/24 -j ACCEPT
   iptables -A INPUT -p vrrp -j DROP
   ```
4. **Replace the self-signed cert** — mount your own:
   ```yaml
   volumes:
     - ./certs/backend.pem:/etc/haproxy/certs/backend.pem:ro
   ```

## Cleanup

```bash
# Stop and remove all containers:
docker compose down

# Remove volumes and images:
docker compose down -v --rmi local
```

## Files

```
Dockerfile                 # Docker image (Alpine, ARM64 + amd64)
docker-compose.yml         # 3-node cluster example
entrypoint.sh              # Config generation + service startup
ha-check-haproxy.sh        # Keepalived health check script
config.sh                  # Shared config — identical on all nodes
node.conf.template         # Node-specific config template
keepalived.conf.template   # Keepalived VRRP config template
haproxy.cfg.template       # HAProxy load balancer config template
samples/
  backends.conf.sample     # Backend server list template
```

## License

MIT — use as you wish.
