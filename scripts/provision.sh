#!/usr/bin/env bash
# Bicep provision wrapper with what-if + deploy.
#
# Usage:
#   bash provision.sh <env> [<extra-az-args>...]
# Example:
#   bash provision.sh dev
#   bash provision.sh prod --confirm-with-what-if   # interactive what-if approval
#
# Conventions:
#   - Bicep at ./bicep/main.bicep
#   - Param file at ./bicep/parameters/<env>.bicepparam
#   - RG: rg-${PROJECT}-${ENV}; created if missing
#   - LOCATION from env or first param-file's location
#   - PROJECT from .env or first param-file's namePrefix

set -euo pipefail

env="${1:?usage: provision.sh <env>}"
shift || true

# Load .env if present
[[ -f .env ]] && source .env

PROJECT="${PROJECT:?Set PROJECT in .env or environment}"
LOCATION="${LOCATION:-westeurope}"
RG="rg-${PROJECT}-${env}"

bicep_file="${BICEP_FILE:-./bicep/main.bicep}"
param_file="${PARAM_FILE:-./bicep/parameters/${env}.bicepparam}"

if [[ ! -f "$bicep_file" ]]; then
  echo "Missing $bicep_file"; exit 2
fi
if [[ ! -f "$param_file" ]]; then
  echo "Missing $param_file. Copy from .example and fill in."; exit 2
fi

echo "── Sanity checks ──"
az account show --query "{sub:name,user:user.name}" -o table

# Ensure RG exists
if ! az group show -n "$RG" &>/dev/null; then
  echo "Creating RG $RG in $LOCATION"
  az group create -n "$RG" -l "$LOCATION" \
    --tags "Environment=${env}" "Project=${PROJECT}" "ManagedBy=bicep"
fi

# Lint Bicep
echo "── Linting Bicep ──"
az bicep build --file "$bicep_file" --stdout > /dev/null

# What-if
echo "── What-if (review carefully) ──"
az deployment group what-if \
    --resource-group "$RG" \
    --template-file "$bicep_file" \
    --parameters "$param_file"

if [[ "${env}" == "prod" || "${1:-}" == "--confirm-with-what-if" ]]; then
  read -p "Proceed with deploy? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# Deploy
echo "── Deploying ──"
deploy_name="${PROJECT}-${env}-$(date +%Y%m%d-%H%M%S)"
az deployment group create \
    --resource-group "$RG" \
    --name "$deploy_name" \
    --template-file "$bicep_file" \
    --parameters "$param_file"

# Save outputs
mkdir -p outputs
az deployment group show -g "$RG" -n "$deploy_name" \
    --query "properties.outputs" -o json > "outputs/${env}.json"
echo "Outputs saved to outputs/${env}.json"

echo "── Done ──"
