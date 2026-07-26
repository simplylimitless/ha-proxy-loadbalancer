# Deployment Checklist

## Before You Start

- [ ] All 3 Proxmox nodes are on the same LAN/subnet
- [ ] You have a spare IP address on that subnet for the VIP (or use an unused /30)
- [ ] SSH access to all 3 nodes as root (or sudo)
- [ ] VRRP_VRID (default 50) is not already in use on your network

## Step 1: Install Dependencies (all 3 nodes)

```bash
# Copy install-dependencies.sh to each node
for node in node1 node2 node3; do
  scp install-dependencies.sh root@$node:/root/
done

# Run on each node
ssh root@node1 bash /root/install-dependencies.sh
ssh root@node2 bash /root/install-dependencies.sh
ssh root@node3 bash /root/install-dependencies.sh
```

## Step 2: Deploy Shared Config (all 3 nodes)

```bash
# Edit config.sh locally first — set your VIP, interface, and backend IPs

for node in node1 node2 node3; do
  scp config.sh root@$node:/etc/haproxy-lb/
done
```

## Step 3: Deploy Node-Specific Config (one per node)

```bash
# Edit node.conf for each node, then deploy

# Node 1 (primary):
sed -e 's/NODE_PRIORITY=110/NODE_PRIORITY=110/' \
    -e 's/NODE_IP="192.168.1.10"/NODE_IP="192.168.1.10"/' \
    node.conf.template > node.conf.node1
scp node.conf.node1 root@node1:/etc/haproxy-lb/node.conf

# Node 2 (backup):
sed -e 's/NODE_PRIORITY=110/NODE_PRIORITY=90/' \
    -e 's/NODE_IP="192.168.1.10"/NODE_IP="192.168.1.11"/' \
    node.conf.template > node.conf.node2
scp node.conf.node2 root@node2:/etc/haproxy-lb/node.conf

# Node 3 (backup):
sed -e 's/NODE_PRIORITY=110/NODE_PRIORITY=90/' \
    -e 's/NODE_IP="192.168.1.10"/NODE_IP="192.168.1.12"/' \
    node.conf.template > node.conf.node3
scp node.conf.node3 root@node3:/etc/haproxy-lb/node.conf
```

## Step 4: Run Deploy Script (all 3 nodes)

```bash
for node in node1 node2 node3; do
  scp deploy.sh root@$node:/etc/haproxy-lb/
  ssh root@$node bash /etc/haproxy-lb/deploy.sh
done
```

## Step 5: Start Services (all 3 nodes)

```bash
for node in node1 node2 node3; do
  ssh root@$node "systemctl enable --now keepalived haproxy"
done
```

## Step 6: Verify

```bash
# Check which node owns the VIP (should be node1, priority=110)
ssh root@node1 "ip addr show eth0 | grep 192.168.1.100"
ssh root@node2 "ip addr show eth0 | grep 192.168.1.100"
ssh root@node3 "ip addr show eth0 | grep 192.168.1.100"

# Test the floating IP
curl -k https://192.168.1.100:8006/api2/json

# Check HAProxy stats
curl -s http://node1:8404/haproxy?stats | grep proxmox

# Check keepalived logs
ssh root@node1 "journalctl -u keepalived --no-pager -n 20"
```

## Step 7: Update DNS

```
# Point your DNS to the floating VIP:
proxmox.example.com.  300  IN  A  192.168.1.100
```

## Step 8: Test Failover

```bash
# Kill HAProxy on the VIP owner — VIP should float to backup
ssh root@node1 "systemctl stop haproxy"
# Wait 4-5 seconds, then verify VIP moved:
ssh root@node2 "ip addr show eth0 | grep 192.168.1.100"

# Restore node1:
ssh root@node1 "systemctl start haproxy"
# VIP should return (preempt mode)
```

## Post-Deployment: Optional Hardening

```bash
# Restrict VRRP multicast to cluster nodes only (iptables)
# Add to each node's firewall:
iptables -A INPUT -p vrrp -s 192.168.1.10/32 -j ACCEPT
iptables -A INPUT -p vrrp -s 192.168.1.11/32 -j ACCEPT
iptables -A INPUT -p vrrp -s 192.168.1.12/32 -j ACCEPT
iptables -A INPUT -p vrrp -j DROP

# Restrict HAProxy stats page to admin network
# Edit /etc/haproxy/haproxy.cfg, update the stats section:
#   stats auth admin:YOUR_PASSWORD
#   acl admin_network src 192.168.1.0/24
#   stats enable if admin_network
```
