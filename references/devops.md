# DevOps - ACR, GitHub Actions, Azure DevOps, deployment patterns

## Default stack

GitHub repo + GitHub Actions + OIDC + Bicep + ACR + (Container Apps | App Service | Functions). 

Use Azure DevOps when the team is already there or the org enforces it.

## ACR (Azure Container Registry)

Defaults:
- **Standard tier** for basic prod, **Premium** for geo-replication / private endpoint / customer keys.
- **Admin user disabled** (use AAD/MI).
- **Anonymous pull disabled**.
- **Image quarantine** + **Defender for Containers** enabled.
- **Geo-replication** for multi-region prod.
- **Image retention policy** to expire old tags.

Bicep: `bicep/modules/acr.bicep`.

RBAC roles:
- `AcrPull` for compute UMI to pull.
- `AcrPush` for build pipeline SP.
- `AcrDelete` for retention scripts.

## GitHub Actions OIDC (the right way)

One-time setup:
```bash
# Create deployment app + SP + federated creds
APP_ID=$(az ad app create --display-name "github-acme-deploy" --query appId -o tsv)
az ad sp create --id $APP_ID >/dev/null
SP_OID=$(az ad sp show --id $APP_ID --query id -o tsv)

# Federate per environment (dev, test, prod)
for ENV in dev test prod; do
  az ad app federated-credential create --id $APP_ID --parameters "{
    \"name\":\"acme-$ENV\",
    \"issuer\":\"https://token.actions.githubusercontent.com\",
    \"subject\":\"repo:Acme/acme-infra:environment:$ENV\",
    \"audiences\":[\"api://AzureADTokenExchange\"]
  }"
done

# Grant role to RG (Contributor for infra deploy)
az role assignment create --assignee $APP_ID --role Contributor \
    --scope /subscriptions/$SUB/resourceGroups/rg-acme-prod
```

GitHub repo Settings → Secrets and variables → Actions → Variables (NOT secrets, since they're not sensitive):
- `AZURE_CLIENT_ID` = $APP_ID
- `AZURE_TENANT_ID` = $TENANT_ID
- `AZURE_SUBSCRIPTION_ID` = $SUB

Workflow:
```yaml
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    environment: prod  # GitHub environment with approvers + protection rules
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - run: az deployment group create -g rg-acme-prod -f main.bicep -p prod.bicepparam
```

`templates/github-actions/bicep-deploy.yml` is the full template.

## Bicep deploy patterns

### Template flow
- `main.bicep` at repo root or `infra/main.bicep`.
- `*.bicepparam` per env.
- Each PR → `bicep-pr-whatif.yml` runs `az deployment group what-if` and posts diff as PR comment.
- Merge to `main` → `bicep-deploy.yml` deploys to Dev (auto), Test (manual), Prod (manual + approvers).

### What-if discipline
Always run `what-if` first. Read the diff. NO blind deploys to prod.
```bash
az deployment group what-if -g $RG -f main.bicep -p prod.bicepparam
```

### Module versioning
Use registry references for shared modules:
```bicep
module kv 'br:acmebicep.azurecr.io/bicep/modules/key-vault:v1.2.0' = { ... }
```
Or local `./modules/...` references for fast iteration. Switch to registry when modules stabilize.

## Azure DevOps (alternative)

Pipelines yaml is similar:
```yaml
- task: AzureCLI@2
  inputs:
    azureSubscription: 'service-connection-with-WIF'
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      az deployment group create -g $RG -f main.bicep -p prod.bicepparam
```

Set up Service Connection with **Workload Identity Federation**:
- Project Settings → Service connections → New → Azure Resource Manager → Workload Identity Federation (automatic).

## Container build/push/deploy

GitHub Actions:
```yaml
- uses: azure/login@v2
- run: az acr login --name acmeacr
- run: docker build -t acmeacr.azurecr.io/api:${{ github.sha }} .
- run: docker push acmeacr.azurecr.io/api:${{ github.sha }}
- run: |
    az containerapp update -n ca-api -g rg-acme-prod \
        --image acmeacr.azurecr.io/api:${{ github.sha }}
```

For App Service: deploy via slot swap.
For AKS: `kubectl set image` or Argo CD / Flux pulling from registry.

## Multi-env strategy

Environments per branch:
- `feature/*` → dev (auto-deploy or PR preview)
- `main` → test
- tag `v*` → prod (gated)

Each env in its own subscription / RG. Bicep parameters file pinned per env. Deploy SP scoped per env.

## Secret rotation in CI/CD

If you must use a secret (third-party tool that doesn't support OIDC):
- Store in KV.
- Pipeline reads from KV via OIDC-authenticated AzureCLI task.
- Auto-rotate via `az ad app credential reset` + KV upsert + restart consumers.

## Validation gates

Before prod deploy:
- Bicep what-if approved.
- Tests pass on Test env.
- Security scan: Defender for Cloud, Trivy on container image, Bicep linter.
- Compliance scan: Azure Policy compliance ≥ 95%.

After deploy:
- Smoke test (HTTP probe + DAX-like data probe).
- Monitor for 30 min: error rate, latency, dependency failures.
- Auto-rollback on red: previous image / Bicep redeploy of previous parameter file.

`scripts/validate.sh` runs the post-deploy probe suite.
