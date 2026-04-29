# Identity - Entra ID, managed identities, RBAC, WIF

## Mental model

- **Tenant** (Entra ID directory): identities (users, groups, apps).
- **Subscription**: billing + RBAC scope.
- **Resource Group / Resource**: RBAC scope.
- **Management Group (MG)**: hierarchical container for subs; policies + RBAC inheritable.

RBAC inheritance: MG → Subscription → RG → Resource. Assign at the lowest scope that works.

## Workload identity types

### System-assigned managed identity (SMI)
- Lifecycle tied to the resource (created with it, destroyed with it).
- One per resource.
- Default for single-resource use.

### User-assigned managed identity (UMI)
- Standalone Azure resource you create.
- Reusable across multiple resources (e.g. App Service + Function + Container App share one UMI for KV access).
- Survives recreation of consuming resources.
- Default for shared use; **default for prod** because immutable identity simplifies RBAC management.

Use **UMI** by default for prod workloads. Bicep: `bicep/modules/managed-identity.bicep`.

### Service Principal (SP)
- App registration in Entra ID (the "application object") + tenant-specific service principal.
- Used for things outside Azure (CI/CD on GitHub, scripts on developer laptops, third-party tools).
- Authentication: **Federated credential (WIF)** preferred over **client secret** or **certificate**.

## Workload Identity Federation (WIF)

Use this for **GitHub Actions, Azure DevOps, Bitbucket, Terraform Cloud, AWS workloads** that need to authenticate to Azure. No secrets to rotate.

GitHub setup:
```bash
APP_ID=$(az ad app create --display-name "deploy-acme-prod" --query appId -o tsv)
SP_OBJECT_ID=$(az ad sp create --id $APP_ID --query id -o tsv)

# Federate to a specific repo + branch (or environment)
az ad app federated-credential create --id $APP_ID --parameters '{
  "name":"acme-prod-main",
  "issuer":"https://token.actions.githubusercontent.com",
  "subject":"repo:Acme/infra:ref:refs/heads/main",
  "audiences":["api://AzureADTokenExchange"]
}'

# Grant subscription/RG-scoped role
az role assignment create --assignee $APP_ID \
    --role Contributor --scope /subscriptions/$SUB_ID/resourceGroups/rg-acme-prod
```

In GitHub Actions:
```yaml
permissions:
  id-token: write    # required to get OIDC token
  contents: read

steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

No secret in `secrets.AZURE_CREDENTIALS`. Tokens are short-lived OIDC tokens exchanged at run time.

For different envs (PR validation vs main deploys vs tags): create separate federated credentials with subject patterns or use `environment:<name>` subjects.

## RBAC roles to know

Built-in (most common):
- **Owner**: full + manage RBAC.
- **Contributor**: full except manage RBAC. Default for "deploy infra" SP.
- **Reader**: read-only.
- **User Access Administrator**: manage RBAC only.

Resource-specific (preferred over Contributor at scope):
- **Key Vault Secrets User**: read secrets via data plane.
- **Key Vault Secrets Officer**: read/write secrets.
- **Key Vault Crypto User / Officer**: keys.
- **Storage Blob Data Reader / Contributor / Owner**: blob data plane (separate from control plane).
- **Cosmos DB Built-in Data Reader / Data Contributor**: data plane.
- **AcrPull / AcrPush**: ACR data plane.
- **Azure Service Bus Data Sender / Receiver / Owner**.
- **Azure Event Hubs Data Sender / Receiver / Owner**.
- **SQL DB Contributor**: control plane only; for data plane use Entra-mapped DB roles.

Pattern: app's UMI gets `Key Vault Secrets User` on the KV, `AcrPull` on the ACR, `Storage Blob Data Reader` on the storage. Never `Contributor` at scope > resource.

`bicep/modules/role-assignment.bicep` is reusable.

## DefaultAzureCredential - write code that just works

In your app code (any language with Azure SDK):

Python:
```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

cred = DefaultAzureCredential()
client = SecretClient(vault_url="https://kv-acme.vault.azure.net", credential=cred)
secret = client.get_secret("db-password")
```

`DefaultAzureCredential` cycles through:
1. Environment variables (`AZURE_CLIENT_ID`, etc.) - useful for SP-based local dev.
2. Workload identity (AKS).
3. Managed identity (App Service / Container Apps / Functions / VM).
4. Azure CLI (`az login` on dev laptop).
5. PowerShell, IntelliJ, VS Code creds.

In all environments, same code path. Local dev uses your `az login`; cloud uses MI; CI uses WIF.

## Entra External ID (customer sign-in for SaaS)

Replaces Azure AD B2C for new tenants in 2026.

Setup (UI - `ui-walkthroughs/external-id-setup.md`):
1. Create an External ID tenant (separate from your workforce tenant).
2. Add user flows (sign-up + sign-in, password reset, MFA).
3. Register your app in the External ID tenant.
4. Customize branding (logo, colors, custom domain).
5. Add identity providers (Google, Microsoft personal, Apple, Facebook) if needed.
6. Configure custom attributes for sign-up.

Apps integrate via OIDC; library: MSAL.js, MSAL.NET, MSAL Python.

## Conditional Access (UI-only, sets organization-wide rules)

Critical for any prod workforce tenant. UI walkthrough: `ui-walkthroughs/conditional-access.md`. Default policies:
- Block legacy auth (POP, IMAP, SMTP) tenant-wide.
- Require MFA for all admin roles.
- Require MFA for risky sign-ins.
- Block access from countries you don't operate in.
- Require compliant device for accessing prod portals.

## PIM (Privileged Identity Management)

Just-in-time elevation for admin roles. Apply to:
- Owner / User Access Administrator on prod subscription.
- Global Admin on tenant.
- Security Admin / Compliance Admin.

Configure: max activation duration (e.g. 4h), require MFA + ticket number on activation, approval required for very high roles.

## Service Principal vs Managed Identity decision

| Need | Pick |
|---|---|
| App in Azure calls Azure resource | **Managed Identity** (UMI for prod) |
| GitHub Actions deploys to Azure | **SP with WIF** |
| Local dev calls Azure | **`az login` + DefaultAzureCredential** |
| Third-party tool (Terraform Cloud, Datadog) | **SP with secret** (rotate via KV-stored secret + monthly rotation script), or WIF if supported |
| Cross-tenant access | **Multi-tenant SP** (more complex; only when needed) |

## Secrets handling baseline

Never:
- Commit secrets to git.
- Store secrets in App Settings as plaintext.
- Use Storage Account access keys (use AAD).
- Use SQL auth (use Entra ID auth).

Always:
- Generate secrets in **Key Vault** (`az keyvault secret set` or auto-rotation policies).
- Reference from app config: `@Microsoft.KeyVault(SecretUri=...)` (App Service / Functions / Container Apps support natively).
- Set KV access via **RBAC mode** (not vault access policies - RBAC is cleaner).
- Auto-rotate where possible (auto-rotated keys for Storage / SQL / Cosmos).
- Soft-delete + purge protection on KV.

## Validation probes

```bash
# What can my MI access?
python scripts/identity.py probe --resource-id <umi-resource-id>

# What roles does an app/SP have?
az role assignment list --assignee <sp-or-umi-app-id> --all -o table

# Test KV access from inside the resource
# (run from Container App console or App Service Kudu)
curl -H "X-IDENTITY-HEADER: $IDENTITY_HEADER" \
     "$IDENTITY_ENDPOINT?resource=https://vault.azure.net&api-version=2019-08-01"
```
