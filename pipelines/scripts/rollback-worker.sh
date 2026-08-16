#!/usr/bin/env bash
# Rollback do worker: sem ingress, reativa a revisao anterior diretamente.
#
# Variaveis de ambiente esperadas: CONTAINER_APP_NAME, RESOURCE_GROUP, PREVIOUS_REVISION

: "${CONTAINER_APP_NAME:?}" "${RESOURCE_GROUP:?}"

if [ -z "${PREVIOUS_REVISION:-}" ]; then
  echo "Nenhuma revisao anterior conhecida; rollback nao pode ser executado."
  exit 1
fi

echo "Revertendo para $PREVIOUS_REVISION"

az containerapp revision activate \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --revision "$PREVIOUS_REVISION"
