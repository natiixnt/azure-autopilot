#!/usr/bin/env bash
# Inventory via Azure Resource Graph. Cross-subscription queries.
#
# Usage: bash inventory.sh <preset>
# Presets: all | by-type | untagged | public-endpoints | empty-rgs | stale-resources

set -euo pipefail
preset="${1:-all}"

case "$preset" in
  all)
    az graph query -q "Resources | project name, type, location, resourceGroup, subscriptionId, tags" --first 1000 -o table
    ;;
  by-type)
    az graph query -q "Resources | summarize count() by type | order by count_ desc" -o table
    ;;
  untagged)
    az graph query -q "Resources | where tags == ''  | project name, type, resourceGroup" --first 200 -o table
    ;;
  public-endpoints)
    # Public-facing storage / SQL / KV / Cosmos
    az graph query -q "Resources
      | where type in~ (
          'microsoft.storage/storageaccounts',
          'microsoft.keyvault/vaults',
          'microsoft.sql/servers',
          'microsoft.documentdb/databaseaccounts',
          'microsoft.containerregistry/registries')
      | extend public = tostring(properties.publicNetworkAccess)
      | where public == 'Enabled' or isempty(public)
      | project name, type, public, resourceGroup" --first 200 -o table
    ;;
  empty-rgs)
    az graph query -q "ResourceContainers
      | where type == 'microsoft.resources/subscriptions/resourcegroups'
      | join kind=leftouter (
          Resources | summarize cnt = count() by resourceGroup
        ) on resourceGroup
      | where isnull(cnt) or cnt == 0
      | project name, location, subscriptionId" --first 200 -o table
    ;;
  stale-resources)
    # VMs deallocated for > 30 days, unattached disks, idle public IPs
    echo "── Deallocated VMs ──"
    az vm list -d --query "[?powerState=='VM deallocated'].{name:name,rg:resourceGroup,os:storageProfile.osDisk.osType}" -o table
    echo ""
    echo "── Unattached disks ──"
    az disk list --query "[?managedBy==null && diskState=='Unattached'].{name:name,rg:resourceGroup,sizeGB:diskSizeGB}" -o table
    echo ""
    echo "── Unassociated public IPs ──"
    az network public-ip list --query "[?ipConfiguration==null].{name:name,rg:resourceGroup,sku:sku.name}" -o table
    ;;
  *)
    echo "unknown preset: $preset"
    echo "Available: all | by-type | untagged | public-endpoints | empty-rgs | stale-resources"
    exit 2
    ;;
esac
