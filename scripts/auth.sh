#!/usr/bin/env bash
# Azure auth helpers + SP+WIF setup for CI/CD.
#
# Usage:
#   bash auth.sh probe                       # diagnose current az login + perms
#   bash auth.sh sp-create <app-name>        # create deployment SP (no secret; WIF later)
#   bash auth.sh sp-federate <app-id> <repo-owner/repo> <env>  # add federated cred for GitHub
#   bash auth.sh assign-rg <app-id> <rg> [<role>]              # grant role on RG (default Contributor)

set -euo pipefail

cmd="${1:-help}"

case "$cmd" in
  probe)
    echo "── Current az context ──"
    az account show --query "{tenant:tenantId,sub:id,subName:name,user:user.name,userType:user.type}" -o jsonc
    echo ""
    echo "── Roles for current principal ──"
    me=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
    if [[ -z "$me" ]]; then
      echo "(not a user; likely SP) - checking by appId:"
      me=$(az account show --query user.name -o tsv)
      app_obj=$(az ad sp show --id "$me" --query id -o tsv 2>/dev/null || true)
      [[ -n "$app_obj" ]] && me=$app_obj
    fi
    az role assignment list --assignee "$me" --all --query "[].{role:roleDefinitionName,scope:scope}" -o table
    echo ""
    echo "── Bicep CLI ──"
    az bicep version || echo "Run 'az bicep install' to install"
    ;;

  sp-create)
    name="${2:?sp-create requires <app-name>}"
    app_id=$(az ad app create --display-name "$name" --sign-in-audience AzureADMyOrg --query appId -o tsv)
    az ad sp create --id "$app_id" >/dev/null
    sp_oid=$(az ad sp show --id "$app_id" --query id -o tsv)
    echo "App ID:        $app_id"
    echo "SP Object ID:  $sp_oid"
    echo "Tenant ID:     $(az account show --query tenantId -o tsv)"
    ;;

  sp-federate)
    app_id="${2:?sp-federate requires <app-id>}"
    repo="${3:?sp-federate requires <owner/repo>}"
    env="${4:?sp-federate requires <env-name>}"
    az ad app federated-credential create --id "$app_id" --parameters "{
      \"name\":\"${repo//\//-}-${env}\",
      \"issuer\":\"https://token.actions.githubusercontent.com\",
      \"subject\":\"repo:${repo}:environment:${env}\",
      \"audiences\":[\"api://AzureADTokenExchange\"]
    }"
    echo "Federated $app_id for $repo env=$env"
    ;;

  assign-rg)
    app_id="${2:?assign-rg requires <app-id>}"
    rg="${3:?assign-rg requires <rg>}"
    role="${4:-Contributor}"
    sub=$(az account show --query id -o tsv)
    az role assignment create --assignee "$app_id" \
        --role "$role" \
        --scope "/subscriptions/${sub}/resourceGroups/${rg}"
    echo "Granted $role to $app_id on $rg"
    ;;

  help|*)
    grep '^#' "$0" | sed 's/^# //'
    ;;
esac
