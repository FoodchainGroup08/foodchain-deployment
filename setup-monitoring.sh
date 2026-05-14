#!/usr/bin/env bash
# setup-monitoring.sh
# Generates prometheus.yml from the template by substituting ACCOUNT2_IP.
# Run this once on Account 1's EC2 before starting the monitoring stack.
#
# Usage:
#   source .env && bash setup-monitoring.sh

set -euo pipefail

if [[ -z "${ACCOUNT2_IP:-}" ]]; then
  echo "ERROR: ACCOUNT2_IP is not set. Add it to your .env and source it first."
  echo "  Example: ACCOUNT2_IP=18.234.56.78"
  exit 1
fi

sed "s/ACCOUNT2_IP_PLACEHOLDER/${ACCOUNT2_IP}/g" prometheus.yml.tpl > prometheus.yml

echo "Generated prometheus.yml with ACCOUNT2_IP=${ACCOUNT2_IP}"
echo ""
echo "Next: docker compose -f docker-compose.account1.yml --env-file .env up -d prometheus grafana"
