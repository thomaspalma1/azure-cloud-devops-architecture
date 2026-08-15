#!/usr/bin/env bash
# Smoke test HTTP: aguarda o endpoint /healthz responder 200 apos o deploy.
# Usado por componentes com ingress (api, web).
#
# Variaveis de ambiente esperadas: CONTAINER_APP_NAME, RESOURCE_GROUP
set -euo pipefail

: "${CONTAINER_APP_NAME:?}" "${RESOURCE_GROUP:?}"

FQDN=$(az containerapp show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv)

for i in $(seq 1 10); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$FQDN/healthz" || echo 000)
  echo "Tentativa $i: HTTP $STATUS"
  if [ "$STATUS" = "200" ]; then exit 0; fi
  sleep 15
done

echo "Smoke test falhou."
exit 1
