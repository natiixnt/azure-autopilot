# Security baseline - Key Vault, Defender, Sentinel, NSG, WAF

## Key Vault

Default for prod:
- **Standard tier** (Premium only if HSM-backed keys required by compliance).
- **RBAC mode** (not vault access policies - RBAC is cleaner, integrates with PIM).
- **Soft-delete** + **purge protection** ON (purge protection is irreversible - accept that).
- **Private endpoint** (vault subresource) + **disable public network**.
- **Diagnostic logs** to LA (capture every secret access for audit).
- **Auto-rotation** for keys + secrets where source supports it (Storage account keys, SQL passwords).

App pattern:
1. App's UMI gets `Key Vault Secrets User`.
2. App config has KV reference: `@Microsoft.KeyVault(SecretUri=https://kv-acme.vault.azure.net/secrets/db-password)`.
3. App Service / Container Apps / Functions resolve via MI at startup; secret never appears in App Settings.

Bicep: `bicep/modules/key-vault.bicep`.

## Microsoft Defender for Cloud

Free tier covers basic recommendations. Paid plans per resource type:
- **Defender for Servers (P2)**: VMs, JIT VM access, file integrity, vulnerability assessment.
- **Defender for App Service**: web app threat detection.
- **Defender for SQL**: SQL injection / anomalous query detection.
- **Defender for Key Vault**: anomalous secret access detection.
- **Defender for Storage**: malware scan on blob upload, anomalous data access.
- **Defender for Containers**: AKS + ACR scanning + runtime detection.
- **Defender for AI Services**: jailbreak / prompt injection detection on Azure OpenAI.

Enable plans matching deployed resources. Set via Bicep at subscription scope.

`scripts/policies.sh enable-defender` automates the per-plan enable.

## Microsoft Sentinel

Layer on top of LA workspace. Use when SIEM/SOAR needed.

Components:
- **Data connectors** (Activity log, Sign-ins, M365, 3rd party).
- **Analytics rules** (KQL detections + scheduled).
- **Workbooks** for SOC dashboards.
- **Playbooks** (Logic Apps) for automated response.
- **Hunting queries** for proactive threat hunt.

Costs scale with ingestion. Don't enable for everything; enable for security-relevant tables.

## Azure Firewall

Use in hub VNet for centralized egress control. Tiers:
- **Standard**: L4 + L7 FQDN filtering, NAT.
- **Premium**: + IDPS, TLS inspection, URL filtering, threat intelligence.

Pair with **Azure Firewall Manager** for policies-as-code.

For workload-level WAF: use **Front Door Premium** (global WAF) or **App Gateway Premium**.

## NSG + ASG

- NSGs at subnet level (not NIC level - too granular).
- ASGs to label workloads (`asg-app`, `asg-db`, `asg-mgmt`); rules reference ASGs.
- Default deny + explicit allows.
- Flow logs v2 + traffic analytics ON.

## DDoS Protection

- **Network Protection** (formerly DDoS Standard): protect public IPs.
- Apply to: Front Door endpoints, App Gateway public IPs, public-facing VMs.
- Cost: ~$2900/mo flat per protection plan + $30 per protected IP. Justify with ROI; small projects can skip.

## Defender for Identity / Entra ID Protection

Detects:
- Anomalous sign-ins.
- Risk-based MFA prompts.
- Compromised accounts.

Required for any tenant with > 10 users; pair with Conditional Access for risk-based policies.

## Cryptography defaults

- **Encryption at rest**: every Azure storage uses platform-managed keys by default. Customer-managed keys (CMK) via KV for compliance.
- **Encryption in transit**: TLS 1.2+ enforced on every public endpoint. Disable older.
- **Customer-managed keys** (BYOK): KV with HSM-backed keys; assign to Storage / SQL / Cosmos.
- **Confidential computing** (CVM, AKS confidential containers): only when threat model requires.

## Identity hardening (UI-only, see `ui-walkthroughs/conditional-access.md`)

- Block legacy auth.
- Require MFA for all admin roles.
- Risk-based MFA (Identity Protection signals).
- Block sign-in from countries you don't operate in.
- Require compliant device for admin portal.
- Session controls: re-auth every X hours for sensitive apps.
- PIM for owner / global admin / privileged roles.

## Resource locks

- `CanNotDelete` on prod RGs and critical resources (KV, prod data, network gateway).
- Locks survive across users (not bound to principal).
- Apply via Bicep or `az lock create`.

## Backup + DR matrix

| Service | Backup type |
|---|---|
| SQL | Auto PITR + LTR |
| Postgres | Auto PITR |
| Cosmos | Continuous (PITR) |
| Storage | Soft-delete + versioning + GRS |
| KV | Soft-delete + purge protection |
| VMs | Recovery Services Vault |
| AKS persistent volumes | Velero or CSI snapshot |

Test restore quarterly. Document RTO/RPO per service.

## Audit checklist (for every prod env)

- [ ] All KVs in RBAC mode + soft-delete + private endpoint
- [ ] All Storage accounts: HTTPS only + min TLS 1.2 + private endpoint + soft-delete
- [ ] All SQL/Postgres: AAD-only + private endpoint + auditing on
- [ ] Defender plans enabled matching resources
- [ ] All RGs have required tags
- [ ] No public SSH/RDP on VMs (use Bastion)
- [ ] All resources send diagnostic logs to LA
- [ ] Conditional Access enforces MFA for admins
- [ ] PIM active for elevated roles
- [ ] Resource locks on prod RGs
- [ ] Budget alerts active
- [ ] Disaster recovery tested in last 90 days
