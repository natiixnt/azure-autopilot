#!/usr/bin/env bash
# Post-deploy validation suite. Run after `provision.sh`.
#
# Usage: bash validate.sh <env>

set -euo pipefail
env="${1:?usage: validate.sh <env>}"
[[ -f .env ]] && source .env
PROJECT="${PROJECT:?Set PROJECT in .env}"
RG="rg-${PROJECT}-${env}"

pass=0; fail=0
check() {
  local desc="$1"; shift
  if "$@" &>/dev/null; then
    echo "✓ $desc"; pass=$((pass+1))
  else
    echo "✗ $desc"; fail=$((fail+1))
  fi
}

echo "── Validating $RG ──"

# Resources exist
check "RG exists"           az group show -n "$RG"
check "LA workspace exists" bash -c "az resource list -g $RG --resource-type Microsoft.OperationalInsights/workspaces --query '[0]' -o tsv | grep -q ."
check "App Insights exists" bash -c "az resource list -g $RG --resource-type Microsoft.Insights/components --query '[0]' -o tsv | grep -q ."
check "KV exists"           bash -c "az resource list -g $RG --resource-type Microsoft.KeyVault/vaults --query '[0]' -o tsv | grep -q ."
check "ACR exists"          bash -c "az resource list -g $RG --resource-type Microsoft.ContainerRegistry/registries --query '[0]' -o tsv | grep -q ."

# KV in RBAC mode + soft-delete
kv_name=$(az keyvault list -g "$RG" --query "[0].name" -o tsv)
if [[ -n "$kv_name" ]]; then
  rbac=$(az keyvault show -n "$kv_name" --query properties.enableRbacAuthorization -o tsv)
  sd=$(az keyvault show -n "$kv_name" --query properties.enableSoftDelete -o tsv)
  pp=$(az keyvault show -n "$kv_name" --query properties.enablePurgeProtection -o tsv)
  [[ "$rbac" == "true" ]] && echo "✓ KV in RBAC mode" && pass=$((pass+1)) || { echo "✗ KV NOT in RBAC mode"; fail=$((fail+1)); }
  [[ "$sd" == "true" ]] && echo "✓ KV soft-delete on" && pass=$((pass+1)) || { echo "✗ KV soft-delete off"; fail=$((fail+1)); }
  if [[ "$env" == "prod" ]]; then
    [[ "$pp" == "true" ]] && echo "✓ KV purge protection on (prod)" && pass=$((pass+1)) || { echo "✗ KV purge protection off in prod"; fail=$((fail+1)); }
  fi
fi

# Storage accounts: HTTPS only + min TLS 1.2
for sa in $(az storage account list -g "$RG" --query "[].name" -o tsv); do
  https=$(az storage account show -n "$sa" -g "$RG" --query supportsHttpsTrafficOnly -o tsv)
  tls=$(az storage account show -n "$sa" -g "$RG" --query minimumTlsVersion -o tsv)
  shared=$(az storage account show -n "$sa" -g "$RG" --query allowSharedKeyAccess -o tsv)
  [[ "$https" == "true" ]] && echo "✓ Storage $sa HTTPS-only" && pass=$((pass+1)) || { echo "✗ Storage $sa allows HTTP"; fail=$((fail+1)); }
  [[ "$tls" == "TLS1_2" ]] && echo "✓ Storage $sa TLS 1.2" && pass=$((pass+1)) || echo "⚠ Storage $sa TLS = $tls"
  [[ "$shared" == "false" ]] && echo "✓ Storage $sa shared key disabled" && pass=$((pass+1)) || { echo "⚠ Storage $sa shared key enabled (use AAD)"; }
done

# Tags policy compliance
echo "── Tag compliance on RG ──"
tags=$(az group show -n "$RG" --query tags -o json)
for required in Environment Project ManagedBy; do
  if echo "$tags" | grep -q "\"$required\""; then
    echo "✓ Tag $required present"; pass=$((pass+1))
  else
    echo "✗ Tag $required missing"; fail=$((fail+1))
  fi
done

# Diagnostic settings: count resources without diag setting
echo "── Resources lacking diagnostic settings ──"
without_diag=0
for rid in $(az resource list -g "$RG" --query "[].id" -o tsv); do
  count=$(az monitor diagnostic-settings list --resource "$rid" --query "length(value)" -o tsv 2>/dev/null || echo "0")
  if [[ "$count" == "0" ]]; then
    type=$(az resource show --ids "$rid" --query type -o tsv 2>/dev/null)
    # Skip types that don't support diag settings
    case "$type" in
      Microsoft.ManagedIdentity/userAssignedIdentities) ;;
      Microsoft.Authorization/*) ;;
      *)
        echo "  no diag: $type ${rid##*/}"
        without_diag=$((without_diag+1))
        ;;
    esac
  fi
done
echo "$without_diag resources without diagnostic settings"

echo ""
echo "── Summary ──"
echo "PASS: $pass"
echo "FAIL: $fail"
[[ $fail -gt 0 ]] && exit 1 || exit 0
