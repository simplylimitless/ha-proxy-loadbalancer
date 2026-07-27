#!/usr/bin/env bash
# =============================================================================
# Generate sample SNI certificates for HAProxy multi-vhost configuration
#
# Usage:
#   ./generate-sni-certs.sh <cert-output-dir>
#
# Example:
#   mkdir -p /etc/haproxy/certs
#   ./generate-sni-certs.sh /etc/haproxy/certs
#
# Creates self-signed certs for:
#   proxmox.example.com
#   git.example.com
#   jenkins.example.com
#   default (wildcard for unknown domains)
#
# Each .pem contains: cert + key (HAProxy format)
# =============================================================================
set -euo pipefail

OUTPUT_DIR="${1:-.}"
mkdir -p "$OUTPUT_DIR"

# Domains to generate certs for
DOMAINS=(
    "proxmox.example.com"
    "git.example.com"
    "jenkins.example.com"
    "default"
)

for domain in "${DOMAINS[@]}"; do
    echo "Generating certificate for ${domain}..."
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "/tmp/${domain}.key" \
        -out "/tmp/${domain}.crt" \
        -days 365 \
        -subj "/CN=${domain}" 2>/dev/null

    # Combine cert + key into HAProxy .pem format
    cat "/tmp/${domain}.crt" "/tmp/${domain}.key" > "${OUTPUT_DIR}/${domain}.pem"
    chmod 600 "${OUTPUT_DIR}/${domain}.pem"

    rm -f "/tmp/${domain}.key" "/tmp/${domain}.crt"
    echo "  -> ${OUTPUT_DIR}/${domain}.pem"
done

echo ""
echo "Certificates generated in ${OUTPUT_DIR}/"
echo "Update haproxy.cfg to reference: ssl crt ${OUTPUT_DIR}/"
