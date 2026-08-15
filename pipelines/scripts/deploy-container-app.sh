#!/usr/bin/env bash
# Atualiza a imagem de um Azure Container App e expõe a revisao anterior
# (via ##vso[task.setvariable]) para permitir rollback em caso de falha
# no smoke test.
#
# Variaveis de ambiente esperadas:
#   CONTAINER_APP_NAME, RESOURCE_GROUP, REGISTRY_NAME, COMPONENT_NAME, IMAGE_TAG
set -euo pipefail

: "${CONTAINER_APP_NAME:?}" "${RESOURCE_GROUP:?}" "${REGISTRY_NAME:?}" "${COMPONENT_NAME:?}" "${IMAGE_TAG:?}"

PREVIOUS=$(az containerapp show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.latestRevisionName -o tsv)

echo "Revisao atual: $PREVIOUS"
echo "##vso[task.setvariable variable=previousRevision]$PREVIOUS"

az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --image "$REGISTRY_NAME.azurecr.io/$COMPONENT_NAME:$IMAGE_TAG"
