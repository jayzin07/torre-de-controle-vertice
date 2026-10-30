#!/usr/bin/env bash
# Dá ao service principal do app minha-torre acesso de leitura à gold e à silver.
#
# O app roda como um service principal próprio, criado no primeiro
# `databricks bundle deploy`. Sem estes grants, o build do app falha
# (o typegen não consegue descrever as queries) e as telas não leem nada.
#
# Uso:
#   bash scripts/conceder-acesso.sh <perfil> [nome-do-app]
#   ex.: bash scripts/conceder-acesso.sh vertice
set -euo pipefail

PERFIL="${1:?informe o perfil do Databricks CLI: bash scripts/conceder-acesso.sh <perfil>}"
APP="${2:-minha-torre}"
CATALOGO="lakehouse_vertice"

# 1. O client id do service principal do app (é ele o "principal" nos grants)
SP=$(databricks apps get "$APP" --profile "$PERFIL" -o json \
  | sed -n 's/.*"service_principal_client_id": *"\([^"]*\)".*/\1/p')

if [ -z "$SP" ]; then
  echo "O app $APP ainda não tem service principal. Rode 'databricks bundle deploy --profile $PERFIL' antes." >&2
  exit 1
fi
echo "Service principal do $APP: $SP"

# 2. USE CATALOG no catálogo
databricks grants update catalog "$CATALOGO" --profile "$PERFIL" \
  --json "{\"changes\": [{\"principal\": \"$SP\", \"add\": [\"USE_CATALOG\"]}]}" > /dev/null
echo "  USE CATALOG em $CATALOGO"

# 3. USE SCHEMA + SELECT na gold e na silver (o SELECT no schema vale para todas as tabelas dele)
for SCHEMA in gold silver; do
  databricks grants update schema "$CATALOGO.$SCHEMA" --profile "$PERFIL" \
    --json "{\"changes\": [{\"principal\": \"$SP\", \"add\": [\"USE_SCHEMA\", \"SELECT\"]}]}" > /dev/null
  echo "  USE SCHEMA + SELECT em $CATALOGO.$SCHEMA"
done

echo "Pronto. Agora: databricks apps deploy $APP --profile $PERFIL"
