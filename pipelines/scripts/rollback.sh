#!/usr/bin/env bash
# Rollback via troca de trafego para a revisao anterior.
# Usado por componentes com ingress (api, web).
#
# Variaveis de ambiente esperadas: CONTAINER_APP_NAME, RESOURCE_GROUP, PREVIOUS_REVISION
set -euo pipefail

: "${CONTAINER_APP_NAME:?}" "${RESOURCE_GROUP:?}"

if [ -z "${PREVIOUS_REVISION:-}" ]; then
  echo "Nenhuma revisao anterior conhecida; rollback nao pode ser executado."
  exit 1
fi

echo "Revertendo para $PREVIOUS_REVISION"

az containerapp ingress traffic set \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --revision-weight "$PREVIOUS_REVISION"=100

exit 1
