# Pattern: Secure landing zone (CAF-aligned)

For: enterprise Azure tenants where multiple workloads will land. Sets up the foundation: management groups, networking hub, policies, identity, observability, governance.

Aligned with Microsoft Cloud Adoption Framework (CAF) "Azure Landing Zone".

## When to use

- Org will run > 3 workloads on Azure long-term.
- Compliance / audit requires central controls.
- Multiple teams need separate billing / RBAC.
- You need a hub-spoke network with shared services.

When NOT to use:
- Tiny project (1 app, 1 team) - use `webapp-saas` directly.
- Existing landing zone in place - extend, don't rebuild.

## Management group hierarchy

```
Tenant Root
└── <Org> (top MG)
    ├── Platform
    │   ├── Identity        ← AD-DS / Entra Connect / privileged identity
    │   ├── Management      ← LA workspace, Sentinel, Automation
    │   └── Connectivity    ← Hub VNet, ExpressRoute, AzFW
    ├── Landing Zones
    │   ├── Corp            ← internal apps with on-prem connectivity
    │   └── Online          ← internet-facing apps
    ├── Decommissioned
    └── Sandbox             ← experimentation, time-boxed
```

Subscriptions are placed under appropriate MGs. Policies + RBAC inherit down.

## Components

### Connectivity sub
- Hub VNet (`/16` per region).
- VPN Gateway / ExpressRoute Gateway.
- **Azure Firewall Premium** (IDPS, TLS inspection).
- Bastion.
- **Private DNS zones** for all PaaS services (linked to spokes).
- **Azure Private DNS Resolver** (inbound + outbound endpoints).

### Identity sub
- Entra Connect server (if hybrid AD).
- PIM-enabled privileged accounts.
- Custom roles (least-privilege per workload).

### Management sub
- Single tenant-wide LA workspace (or per-region) for platform logs.
- Sentinel on top.
- Defender for Cloud at MG scope.
- Azure Automation account for runbooks (VM patch, backup orchestration).
- Update Management.

### Landing Zone subs (per-workload)
- Spoke VNet peered to hub.
- UDR on spoke 0.0.0.0/0 → AzFW in hub.
- Workload-specific RGs.

## Policies (apply at top MG)

Enforce via Azure Policy (`templates/policies/`):

| Policy | Effect |
|---|---|
| Allowed locations | Deny resources outside region whitelist |
| Required tags (CostCenter, Environment, Owner, Project) | Deny resource creation |
| Allowed SKUs (per resource type) | Deny large/expensive in non-prod |
| Storage HTTPS only + min TLS 1.2 | Deny |
| KV soft-delete + purge protection | Deny KV without |
| SQL TDE on | DeployIfNotExists |
| Diagnostic settings to LA | DeployIfNotExists |
| Defender plans enabled | DeployIfNotExists |
| Resource group must have lock | Audit (warn but allow) |

Use **Microsoft built-in initiatives** (CIS, NIST 800-53, ISO 27001, PCI DSS) and assign at MG level.

## Bicep at subscription / MG scope

Subscription-scope Bicep:
```bicep
targetScope = 'subscription'

module rgPlatform 'modules/resource-group.bicep' = {
  params: { name: 'rg-platform-mgmt-prod', location: 'westeurope', tags: tags }
}

module hub 'patterns/hub-vnet.bicep' = {
  scope: resourceGroup('rg-connectivity-prod')
  params: { ... }
}

module la 'modules/log-analytics.bicep' = {
  scope: resourceGroup('rg-platform-mgmt-prod')
  params: { name: 'la-platform-prod', ... }
}
```

Management-group-scope Bicep:
```bicep
targetScope = 'managementGroup'

module policy 'modules/policy-assignment.bicep' = {
  params: {
    name: 'require-tags'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/...'
    parameters: { tagName: { value: 'CostCenter' } }
  }
}
```

## Identity baseline

- **Custom RBAC roles**: `Workload Owner`, `Workload Operator`, `Workload Reader` per landing zone.
- **PIM activation** for high-privilege roles, with MFA + ticket reason.
- **Conditional Access**: block legacy auth, require MFA, country block, compliant device for admin.
- **Break-glass accounts**: 2 cloud-only accounts excluded from CA, hardware MFA, monitored.

## Observability baseline

- All subscriptions emit activity logs to platform LA.
- Defender for Cloud at MG scope, plans enabled per resource type.
- Sentinel on platform LA, with connectors to Entra ID, M365, third-party.
- Alerts → ITSM (ServiceNow / Jira) integration.

## Cost baseline

- Tags policy enforced.
- Budgets per landing zone subscription.
- Reserved instances purchased centrally, distributed via shared scope.
- Cost reports per MG → finance.

## Deployment sequencing

1. Create top MG + child MGs.
2. Move/create platform subs (Identity, Management, Connectivity).
3. Provision hub VNet + AzFW + Bastion + LA + Sentinel.
4. Apply tenant-wide policies at top MG.
5. Provision first landing-zone sub (e.g. Corp / Online).
6. Onboard first workload to landing zone.

`workflows/secure-landing-zone.md` walks the full sequence with az CLI + Bicep.

## ALZ accelerator vs. roll-your-own

Microsoft maintains the **Azure Landing Zone (ALZ) Accelerator** - a Bicep / Terraform / Portal deployment of the full pattern. Use it as a starting point if greenfield enterprise. Repo: `Azure/ALZ-Bicep` on GitHub.

Customize:
- Region selection.
- MG hierarchy names.
- Policy initiative scope + exemptions.
- Hub network sizing.

## Sizing considerations

- Hub VNet `/16` is generous; downsize to `/22` for smaller orgs.
- AzFW Premium ~$1500/mo + traffic. Justify with TLS inspection / IDPS need.
- Sentinel cost = ingestion-based; tune table opt-out.
- Multiple regions = multiply hub costs.
