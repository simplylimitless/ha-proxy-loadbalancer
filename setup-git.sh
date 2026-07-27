#!/usr/bin/env bash
set -euo pipefail
cd /home/hwong/dev/sandbox/ha-proxy-loadbalancer
git init
git remote add origin git@github.com:simplylimitless/ha-proxy-loadbalancer.git
git add -A
git commit -m "Initial commit: HA Proxy Load Balancer for any service with test suite

- Floating VIP + load-balanced proxy for any service
- Keepalived VRRP for high availability
- HAProxy with active health checks
- Docker deployment support
- Comprehensive test suite (211 assertions)"
git push -u origin main
