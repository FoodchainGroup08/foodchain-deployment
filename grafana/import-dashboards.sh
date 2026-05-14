#!/usr/bin/env bash
# import-dashboards.sh
# Imports community dashboards from grafana.com into the running Grafana instance.
# Run this once after Grafana is up:
#   bash grafana/import-dashboards.sh
#
# Dashboards imported:
#   4701  — JVM (Micrometer)          — heap, GC, threads, classes
#   19004 — Spring Boot 3.x Statistics — HTTP throughput, latency, errors

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASSWORD:-admin}"
DATASOURCE_UID="prometheus"

import_dashboard() {
  local id=$1
  local name=$2
  echo -n "Importing '${name}' (ID ${id})... "

  payload=$(cat <<EOF
{
  "dashboard": $(curl -sf "https://grafana.com/api/dashboards/${id}/revisions/latest/download"),
  "folderId": 0,
  "overwrite": true,
  "inputs": [{"name": "DS_PROMETHEUS", "type": "datasource", "pluginId": "prometheus", "value": "${DATASOURCE_UID}"}]
}
EOF
)

  result=$(curl -sf -X POST "${GRAFANA_URL}/api/dashboards/import" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -H "Content-Type: application/json" \
    -d "${payload}" 2>&1)

  if echo "${result}" | grep -q '"status":"success"'; then
    echo "OK"
  else
    echo "FAILED — ${result}"
  fi
}

echo "Waiting for Grafana at ${GRAFANA_URL}..."
until curl -sf "${GRAFANA_URL}/api/health" > /dev/null; do sleep 3; done
echo "Grafana is up."
echo ""

import_dashboard 4701  "JVM (Micrometer)"
import_dashboard 19004 "Spring Boot 3.x Statistics"

echo ""
echo "Done. Open Grafana at ${GRAFANA_URL} (user: ${GRAFANA_USER})"
