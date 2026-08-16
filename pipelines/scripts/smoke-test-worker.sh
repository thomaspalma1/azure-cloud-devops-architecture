#!/usr/bin/env bash
# Smoke test do worker: sem ingress HTTP, entao valida que a revisao
# publicada chegou ao estado "Running".
#
# Variaveis de ambiente esperadas: CONTAINER_APP_NAME, RESOURCE_GROUP

: "${CONTAINER_APP_NAME:?}" "${RESOURCE_GROUP:?}"

REVISION=$(az containerapp show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.latestRevisionName -o tsv)

for i in $(seq 1 10); do
  STATE=$(az containerapp revision show \
    --name "$CONTAINER_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --revision "$REVISION" \
    --query properties.runningState -o tsv)

  echo "Tentativa $i: estado $STATE"
  if [ "$STATE" = "Running" ]; then exit 0; fi
  sleep 15
done

echo "Smoke test falhou."
exit 1
