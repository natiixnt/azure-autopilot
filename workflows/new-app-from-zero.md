## Workflow: greenfield SaaS app on Azure (zero-to-prod)

End-to-end recipe for a new web app/API + DB + cache + KV + CDN. Estimated time: 1–2 days for first env, hours for additional envs.

## Day 0 - Discovery (1 hour)

Capture in `discovery.md`:

1. **What**: 1-sentence description of what we're building.
2. **Audience**: count, roles, internal/external.
3. **Stack**: language/runtime (Node, Python, .NET, Java, Go, …), DB preference (Postgres/SQL/Cosmos).
4. **Region**: where users are (PL → `westeurope` or `polandcentral`).
5. **Scale expectations**: requests/sec, DB size, GB upload.
6. **Compliance**: GDPR, residency.
7. **Integrations**: payments, email, AI, CRM, on-prem.
8. **CI/CD**: GitHub or Azure DevOps.
9. **Team**: who deploys.
10. **Budget envelope**: monthly ceiling per env.

Output: `discovery.md` + a 1-page mermaid architecture from `patterns/webapp-saas.md`. Show user; agree.

## Day 1 - Foundation

### 1. Authenticate
```bash
az login
az account set -s <subscription-id>
bash ~/.claude/skills/azure-autopilot/scripts/auth.sh probe
```

### 2. Set up CI/CD identity (WIF)
```bash
APP_NAME="${PROJECT}-deploy"
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID"

# Federate per env (loop)
for env in dev test prod; do
  bash ~/.claude/skills/azure-autopilot/scripts/auth.sh sp-federate \
      "$APP_ID" "Acme/${PROJECT}-infra" "$env"
done

# Show what to put in GitHub repo Variables
echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)"
```

### 3. Provision dev RG + foundation
```bash
# Copy starter Bicep
cp -r ~/.claude/skills/azure-autopilot/bicep ./infra
cp -r ~/.claude/skills/azure-autopilot/scripts ./scripts
cp ~/.claude/skills/azure-autopilot/templates/.env.example .env

# Edit .env with PROJECT, LOCATION
# Edit infra/parameters/dev.bicepparam.example -> dev.bicepparam (fill sqlAdminGroupObjectId)

# What-if + deploy
bash scripts/provision.sh dev
bash scripts/validate.sh dev
```

Output: RG created, LA + AI + KV + ACR + Postgres + VNet + Container Apps env + 1 placeholder app.

### 4. Grant SP RG-Contributor for CI/CD
```bash
bash scripts/auth.sh assign-rg "$APP_ID" "rg-${PROJECT}-dev" Contributor
# Repeat for test, prod
```

### 5. Push first image to ACR (manual one-shot)
```bash
ACR_NAME=$(jq -r .acrLoginServer.value outputs/dev.json | cut -d. -f1)
az acr login --name "$ACR_NAME"
az acr build --registry "$ACR_NAME" --image app:v0 --file Dockerfile .

# Update Container App
az containerapp update -n "ca-${PROJECT}-app-dev" -g "rg-${PROJECT}-dev" \
    --image "${ACR_NAME}.azurecr.io/app:v0"
```

### 6. Verify
```bash
APP_FQDN=$(az containerapp show -n "ca-${PROJECT}-app-dev" -g "rg-${PROJECT}-dev" --query properties.configuration.ingress.fqdn -o tsv)
curl -s "https://${APP_FQDN}/health" || echo "App not ready / no /health endpoint"
```

## Day 2 - Test + Prod envs

```bash
bash scripts/provision.sh test
bash scripts/validate.sh test

bash scripts/provision.sh prod
bash scripts/validate.sh prod
```

Each env gets its own RG, KV, DB, ACR, etc. SKUs differ per env (see `bicep/main.bicep` ternary expressions).

## Day 2 - Wire CI/CD

Drop into the app repo `.github/workflows/`:
- `bicep-pr-whatif.yml` - runs on PR; shows diff.
- `bicep-deploy.yml` - runs on merge to main; deploys to dev → test → prod (gated).
- `container-build-deploy.yml` - builds image, pushes to ACR, updates Container App.

Templates at `~/.claude/skills/azure-autopilot/templates/github-actions/`.

## Day 2 - Configure DB + secrets

```bash
# Connect to Postgres as the AAD admin (a member of sqlAdminGroup)
PG_FQDN=$(jq -r .postgresFqdn.value outputs/prod.json)
TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)
PGPASSWORD=$TOKEN psql "host=$PG_FQDN dbname=postgres user=admin@upn.com sslmode=require" \
    -c "CREATE DATABASE app;"

# Create role for the UMI
UMI_PRINCIPAL=$(jq -r .managedIdentityPrincipalId.value outputs/prod.json)
PGPASSWORD=$TOKEN psql "host=$PG_FQDN dbname=app user=admin@upn.com sslmode=require" <<SQL
CREATE ROLE "umi-${PROJECT}-prod" LOGIN;
GRANT CONNECT ON DATABASE app TO "umi-${PROJECT}-prod";
GRANT USAGE, CREATE ON SCHEMA public TO "umi-${PROJECT}-prod";
SQL
```

Store any third-party secrets (Stripe API key, Mailgun, etc.) in KV:
```bash
KV_URI=$(jq -r .keyVaultUri.value outputs/prod.json)
KV_NAME=$(echo "$KV_URI" | sed 's|https://\([^.]*\).*|\1|')
az keyvault secret set --vault-name "$KV_NAME" --name stripe-secret-key --value "$STRIPE_KEY"
```

App reads via KV reference syntax in Container App settings (already wired by Bicep when secrets defined).

## Day 2 - Custom domain + cert (if Front Door in stack)

```bash
# In Bicep, FD endpoint provides hostname like ca-acme.azurefd.net
# Add custom domain:
az afd custom-domain create \
    --resource-group "rg-${PROJECT}-prod" \
    --profile-name "fd-${PROJECT}-prod" \
    --custom-domain-name app-acme-com \
    --host-name app.acme.com \
    --certificate-type ManagedCertificate

# Then create CNAME at DNS: app.acme.com -> ca-acme.azurefd.net
# Add TXT for validation (token shown by command)
```

## Day 3 - Observability + alerts

Already auto-wired by Bicep (LA + AI + diagnostic settings + action group). Verify:
```bash
az monitor app-insights component show -g "rg-${PROJECT}-prod" --query "name"
# Open in Portal → Application Insights → Live Metrics; should see traffic
```

Add custom alert rules per business need (e.g. order processing failure rate > 1%):
```bash
az monitor scheduled-query create -g "rg-${PROJECT}-prod" \
    --name "order-failure-rate" \
    --scopes <ai-resource-id> \
    --condition "count traces | where customDimensions.event == 'order_failed' > 5" \
    --action <action-group-id>
```

## Day 3 - Handover

Deliver:
- `discovery.md` + architecture mermaid
- `infra/` repo (Bicep + parameters + .gitignore for `.env`/`outputs/`)
- `.env.example`
- README with onboarding for new devs
- 30-min walkthrough with the team
- Runbooks for: deploy, rollback, rotate secret, restore DB, restore KV secret, scale up

## Validation checklist

- [ ] `auth.sh probe` shows context + roles
- [ ] All 3 envs deployed via `provision.sh`
- [ ] `validate.sh` passes for each env
- [ ] First image deployed to dev's Container App and serves traffic
- [ ] CI/CD: PR shows what-if; merge auto-deploys to dev
- [ ] CD: tag/manual approval for test → prod
- [ ] Custom domain on FD points to prod
- [ ] App Insights showing traces
- [ ] Action group fires on test alert
- [ ] Budget alert configured at 80%
- [ ] All secrets in KV; app reads via MI
- [ ] Postgres backup tested (PITR restore to scratch)
- [ ] No public endpoints on data plane in prod
