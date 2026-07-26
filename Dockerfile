# =============================================================================
# HA Load Balancer — Docker image for Raspberry Pi (ARM64)
# Runs keepalived (VRRP floating VIP) + HAProxy (load balancer) in one container
# =============================================================================
FROM alpine:3.20

# Install runtime dependencies
# - keepalived: VRRP for floating VIP
# - haproxy:    load balancer with active health checks
# - socat:      HAProxy socket access for health check script
# - openssl:    generate self-signed cert for HAProxy frontend
# - iproute2:   ip/ss for network diagnostics (debugging)
RUN apk add --no-cache \
    keepalived \
    haproxy \
    socat \
    openssl \
    iproute2 \
    procps

# Create directories for runtime state and certificates
RUN mkdir -p \
    /etc/haproxy/certs \
    /run/haproxy \
    /etc/keepalived \
    /etc/haproxy-lb

# Copy entrypoint and health check scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ha-check-haproxy.sh /usr/local/bin/ha-check-haproxy.sh

RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/ha-check-haproxy.sh

# Ports — HAProxy frontend (8006), HTTP redirect (8007), stats (8404)
EXPOSE 8006 8007 8404

# Health check: is the VIP-responsive? (skip during build)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD \
    pgrep haproxy || exit 1

# Entrypoint generates configs and starts both services
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--foreground"]
