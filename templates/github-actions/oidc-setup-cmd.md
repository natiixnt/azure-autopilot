# GitHub Actions OIDC - one-time setup

Run once per project repo to wire WIF between GitHub and Azure (no client secrets).

## 1. Create app registration + SP

```bash
APP_NAME="${PROJECT}-deploy"
REPO="OWNER/${PROJECT}-infra"   # e.g. acme/acme-infra

APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID" >/dev/null

echo "App ID: $APP_ID"
echo "Tenant ID: $(az account show --query tenantId -o tsv)"
echo "Subscription ID: $(az account show --query id -o tsv)"
```

## 2. Federate per environment

GitHub environments (Settings → Environments) match the `environment:` field in workflows.
Federated subject: `repo:${REPO}:environment:${ENV}`.

```bash
for ENV in dev test prod; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\":\"${PROJECT}-${ENV}\",
    \"issuer\":\"https://token.actions.githubusercontent.com\",
    \"subject\":\"repo:${REPO}:environment:${ENV}\",
    \"audiences\":[\"api://AzureADTokenExchange\"]
  }"
done
```

For PRs (no environment): use `pull_request` subject pattern `repo:${REPO}:pull_request`.
For tags: `repo:${REPO}:ref:refs/tags/v*`.
For main branch: `repo:${REPO}:ref:refs/heads/main`.

## 3. Grant RBAC per env (Contributor on RG)

```bash
SUB=$(az account show --query id -o tsv)
for ENV in dev test prod; do
  az role assignment create --assignee "$APP_ID" \
      --role Contributor \
      --scope "/subscriptions/${SUB}/resourceGroups/rg-${PROJECT}-${ENV}"
done
```

For broader control plane changes: grant at sub scope (Contributor) - but only if needed.

## 4. Configure GitHub repo

Repo Settings → Secrets and variables → Actions → Variables:
- `AZURE_CLIENT_ID` = $APP_ID
- `AZURE_TENANT_ID` = `$(az account show --query tenantId -o tsv)`
- `AZURE_SUBSCRIPTION_ID` = `$(az account show --query id -o tsv)`
- `PROJECT` = your project slug

(These are public Variables, not Secrets - they're not sensitive when using OIDC.)

## 5. Create environments

Repo Settings → Environments → New environment:
- `dev` - no protection rules
- `test` - required reviewers: BI lead
- `prod` - required reviewers: ≥2 approvers, deployment branch policy: `main` or tags

## 6. Verify

Push a PR with a no-op Bicep change. The `bicep-pr-whatif.yml` workflow should run, post a comment with the diff. Merge → `bicep-deploy.yml` runs to dev.

## Troubleshooting

- `AADSTS70021`: federated credential subject doesn't match. Confirm exact subject pattern (`environment:dev` vs `ref:refs/heads/main`).
- `AuthorizationFailed`: SP not yet granted RBAC, or scope mismatch. Re-check `az role assignment list --assignee $APP_ID --all`.
- Workflow `permissions:` missing `id-token: write` → token request fails.
