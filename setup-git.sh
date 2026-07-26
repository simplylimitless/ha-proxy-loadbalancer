#!/usr/bin/env bash
set -euo pipefail
cd /home/hwong/dev/sandbox/ha-proxy-loadbalancer
git init
git remote add origin git@github.com:simplylimitless/ha-proxy-loadbalancer.git
git add -A
git commit -m "Initial commit: HA Proxy Load Balancer for Proxmox cluster with test suite

- Floating VIP + load-balanced proxy for Proxmox web interface
- Keepalived VRRP for high availability
- HAProxy with active health checks
- Docker and bare-metal deployment support
- Comprehensive test suite (209 assertions)"
git push -u origin main
