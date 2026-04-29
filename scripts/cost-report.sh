#!/usr/bin/env bash
# Cost reporting via Cost Management API.
#
# Usage:
#   bash cost-report.sh --days 30
#   bash cost-report.sh --days 30 --group-by ResourceGroupName
#   bash cost-report.sh --days 30 --group-by ResourceType
#   bash cost-report.sh --month 2026-04

set -euo pipefail

days=30
group_by="ResourceGroup"
month=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) days="$2"; shift 2 ;;
    --group-by) group_by="$2"; shift 2 ;;
    --month) month="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

sub=$(az account show --query id -o tsv)

if [[ -n "$month" ]]; then
  start_date="${month}-01"
  end_date=$(date -j -v+1m -f '%Y-%m-%d' "$start_date" '+%Y-%m-%d' 2>/dev/null || date -d "${start_date} +1 month" '+%Y-%m-%d')
else
  start_date=$(date -u -j -v-${days}d '+%Y-%m-%d' 2>/dev/null || date -u -d "$days days ago" '+%Y-%m-%d')
  end_date=$(date -u '+%Y-%m-%d')
fi

echo "Cost from $start_date to $end_date, grouped by $group_by"

az consumption usage list \
    --start-date "$start_date" \
    --end-date "$end_date" \
    --max-items 5000 \
    --query "[].{rg:instanceLocation,name:instanceName,type:meterDetails.meterCategory,cost:pretaxCost,date:usageStart}" \
    -o tsv \
| awk -v gb="$group_by" '
    BEGIN { OFS="\t" }
    {
      if (gb == "ResourceGroupName" || gb == "ResourceGroup") key=$1
      else if (gb == "ResourceType") key=$3
      else key=$2
      sum[key] += $4
    }
    END {
      for (k in sum) printf "%-50s\t%10.2f\n", k, sum[k]
    }' \
| sort -k2 -nr \
| head -50
