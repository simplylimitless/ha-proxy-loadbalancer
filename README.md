# HA Load Balancer for Proxmox Cluster

A floating VIP + load-balanced proxy for high-availability access to a Proxmox cluster's web interface.

> **Running on Raspberry Pi?** See [Docker-README.md](Docker-README.md) for containerized deployment.

## Quick Start

### Docker (Raspberry Pi)

```bash
docker build -t ha-lb:latest .
docker run -d --network host --privileged \
  -e VIP_ADDRESS=192.168.1.100 \
  -e VRRP_INTERFACE=eth0 \
  -e VRRP_VRID=50 \
  -e NODE_PRIORITY=110 \
  -e BACKENDS_LIST="192.168.1.10:8006,192.168.1.11:8006,192.168.1.12:8006" \
  ha-lb:latest
```

[Full Docker docs →](Docker-README.md)

### Bare metal (apt)

```bash
sudo apt install keepalived haproxy socat openssl
# Copy configs, then:
sudo bash deploy.sh
sudo systemctl enable --now keepalived haproxy
```

[Full bare-metal docs →](DEPLOY-CHECKLIST.md)

## Architecture

```
                   DNS: proxmox.example.com
                          ↓
                    Floating VIP (192.168.1.100)
                          ↓
            Only the VIP-owner node runs HAProxy
                          ↓
            HAProxy health-checks all 3 Proxmox nodes
                          ↓
              Proxmox Node 1 (:8006)  ◄── healthy
              Proxmox Node 2 (:8006)  ◄── healthy
              Proxmox Node 3 (:8006)  ◄── healthy
```

### Two layers of failover:

| Layer | Technology | What it protects against |
|-------|-----------|-------------------------|
| **Node failure** | Keepalived (VRRP) | VIP floats to another node if the owner dies |
| **Backend failure** | HAProxy health checks | Traffic routed around a dead Proxmox node |
| **Proxy failure** | `chk_haproxy` script | HAProxy crash triggers VIP failover via keepalived |

## Files

```
Dockerfile                 # Docker image (Alpine, ARM64 + amd64)
docker-compose.yml         # 3-node cluster example
entrypoint.sh              # Config generation + service startup (Docker)
Docker-README.md           # Docker deployment docs
config.sh                  # Bare-metal shared config — identical on all nodes
node.conf.template         # Bare-metal node-specific config
keepalived.conf.template   # Keepalived VRRP config template
haproxy.cfg.template       # HAProxy load balancer config template
ha-check-haproxy.sh        # Keepalived health check script
deploy.sh                  # Merges templates + configs → /etc/
install-dependencies.sh    # Installs packages, kernel params
DEPLOY-CHECKLIST.md        # Bare-metal deployment checklist
samples/
  backends.conf.sample     # Backend server list template
```

## Quick Start

### 1. Install dependencies on ALL three nodes

```bash
# Copy install-dependencies.sh to each node, then:
sudo bash install-dependencies.sh
```

### 2. Configure shared settings

Edit `config.sh` — set your network, VIP, and backend IPs:

```bash
# Edit on your workstation, then copy to ALL nodes:
scp config.sh node1:/etc/haproxy-lb/
scp config.sh node2:/etc/haproxy-lb/
scp config.sh node3:/etc/haproxy-lb/
```

Key fields:
- `VIP_ADDRESS` — the floating IP (clients/DNS point here)
- `VRRP_INTERFACE` — the LAN interface on each node (e.g., `eth0`, `eno1`)
- `BACKENDS` — list all 3 Proxmox node IPs:ports
- `VRRP_VRID` — must be unique on your network (0–255)

### 3. Configure per-node settings

Copy `node.conf.template` to each node as `/etc/haproxy-lb/node.conf` and edit:

```bash
# Node 1 (primary owner):
NODE_PRIORITY=110
NODE_IP=192.168.1.10

# Node 2 (backup):
NODE_PRIORITY=90
NODE_IP=192.168.1.11

# Node 3 (backup):
NODE_PRIORITY=90
NODE_IP=192.168.1.12
```

```bash
scp node.conf.node1 node1:/etc/haproxy-lb/node.conf
scp node.conf.node2 node2:/etc/haproxy-lb/node.conf
scp node.conf.node3 node3:/etc/haproxy-lb/node.conf
```

### 4. Deploy configs on each node

```bash
# On EACH node:
sudo cp config.sh /etc/haproxy-lb/
sudo bash /etc/haproxy-lb/deploy.sh
```

### 5. Start services

```bash
# On EACH node:
sudo systemctl enable --now keepalived haproxy
```

### 6. Verify

```bash
# Check which node holds the VIP (should be priority=110 node):
ip addr show eth0 | grep "inet 192.168.1.100"

# Check keepalived logs:
sudo journalctl -u keepalived -f

# Check HAProxy logs:
sudo journalctl -u haproxy -f

# Test the floating IP:
curl -k https://192.168.1.100:8006/api2/json

# Check HAProxy stats:
# Open http://<any-node-ip>:8404/haproxy?stats
```

## How It Works

### Keepalived VRRP

- All 3 nodes run keepalived and advertise VRRP heartbeat every second
- The node with highest `priority` wins and owns the VIP
- If the owner stops advertising (crash, network partition), backups take over
- The `chk_haproxy` script lowers priority by 20 if HAProxy is dead
- Preempt mode (default): higher-priority node reclaims VIP when it recovers

### HAProxy Health Checks

- HAProxy sends `GET /api2/json` to each Proxmox node every 2 seconds
- Expected responses: `200` (public API) or `401` (authenticated API) — both mean "alive"
- A backend is marked down after 3 consecutive failures (`fall 3`)
- A backend recovers after 2 consecutive successes (`rise 2`)
- SSL verification is disabled for self-signed Proxmox certs

### HAProxy → Keepalived Integration

When HAProxy crashes:
1. `chk_haproxy.sh` detects the failure (process not running, socket unresponsive)
2. Keepalived lowers the node's VRRP priority by 20
3. A backup node (priority 90 → now effectively 90 vs 90) takes the VIP
4. Services restart — normal operations resume on the new VIP owner

## Configuration Reference

### config.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `VIP_ADDRESS` | `192.168.1.100` | Floating IP for clients |
| `VIP_SUBNET` | `24` | CIDR mask |
| `VRRP_INTERFACE` | `eth0` | LAN interface name |
| `VRRP_VRID` | `50` | VRRP router ID (unique per group) |
| `BACKENDS` | — | Array of `IP:PORT` for Proxmox nodes |
| `HC_INTERVAL` | `2000` | HAProxy health check interval (ms) |
| `HC_TIMEOUT` | `5000` | HAProxy health check timeout (ms) |

### node.conf

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_PRIORITY` | `110` | VRRP priority (1–254; higher wins) |
| `NODE_IP` | — | This node's IP on VRRP interface |

## Troubleshooting

### VIP not appearing

```bash
# Check keepalived status
sudo systemctl status keepalived

# Check for config errors
sudo keepalived -t -f /etc/keepalived/keepalived.conf

# Check kernel param (must be enabled):
sysctl net.ipv4.ip_nonlocal_bind
# Should return: net.ipv4.ip_nonlocal_bind = 1
```

### VIP flapping (frequent failover)

- Increase `advert_int` in keepalived (default 1s)
- Check for network issues — VRRP multicast must reach all nodes
- Ensure `VRRP_VRID` is unique on your network (conflicts cause chaos)
- Check auth password matches across all nodes

### HAProxy shows all backends down

```bash
# Check if Proxmox nodes are reachable from the VIP-owner
curl -kv https://192.168.1.10:8006/api2/json

# Check HAProxy backend status
curl -s http://localhost:8404/haproxy?stats | grep proxmox

# Check HAProxy logs
sudo journalctl -u haproxy --since "5 minutes ago" | grep -i backend
```

### Proxmox console (VM viewer) doesn't work

Proxmox console uses WebSocket connections through port 8006. HAProxy handles these natively — no extra config needed. If consoles fail:

```bash
# Check WebSocket passthrough in HAProxy logs
sudo journalctl -u haproxy | grep -i websocket

# Verify SSL is terminating correctly
openssl s_client -connect 192.168.1.100:8006 -servername 192.168.1.100
```

### Force VIP failover (testing)

```bash
# On the current VIP owner, stop HAProxy to trigger priority downgrade:
sudo systemctl stop haproxy
# Wait ~4 seconds — VIP should float to the next node

# Restore:
sudo systemctl start haproxy
# With preempt, VIP returns to highest-priority node
```

### Reset VIP ownership

```bash
# On the node that should become primary:
sudo systemctl restart keepalived
```

## Security Notes

1. **Change the VRRP auth password** — edit `auth_pass` in `keepalived.conf.template`
2. **Consider firewall rules** — restrict VRRP multicast (protocol 112) to trusted nodes:
   ```bash
   # iptables example: only allow VRRP from cluster nodes
   iptables -A INPUT -p 112 -s 192.168.1.10/32 -j ACCEPT
   iptables -A INPUT -p 112 -s 192.168.1.11/32 -j ACCEPT
   iptables -A INPUT -p 112 -s 192.168.1.12/32 -j ACCEPT
   iptables -A INPUT -p 112 -j DROP
   ```
3. **Stats endpoint** — the HAProxy stats page (`:8404`) should be firewalled to your admin network
4. **Proxmox user** — consider creating a dedicated read-only API user for health checks

## Alternative: Nginx Instead of HAProxy

This project uses HAProxy because it has native active health checks and keepalived integration. If you prefer nginx:

- Use `nginx` with `proxy_pass` to the backends
- Health checks must be passive (nginx only marks servers down after connection failures)
- Use the `ngx_http_lua_upstream` module or `nginx-plus` for active health checks
- VIP failover still works the same with keepalived (just remove the `chk_haproxy` track script)

## License

MIT — use as you wish.
