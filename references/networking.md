# Networking - VNet, NSG, private endpoints, hub-spoke

## When you need a VNet

You don't always. Public-default is fine when:
- Internal tool < 20 users.
- All consumers are internet-based (SaaS for external customers).
- Low compliance bar.

You DO need a VNet when:
- On-prem connectivity (VPN / ExpressRoute).
- Service-to-service traffic should not cross public internet.
- Compliance demands network isolation (PCI, HIPAA).
- Private endpoints to PaaS (KV, Storage, SQL, Cosmos) needed.

## Default VNet layout (single-region)

```
VNet 10.X.0.0/16  (X = environment digit; dev=10, test=20, prod=30)
├── snet-compute     10.X.1.0/24    Container Apps env, App Service VNet integration, AKS nodes
├── snet-data        10.X.2.0/24    Private endpoints for KV, Storage, SQL, Cosmos
├── snet-mgmt        10.X.3.0/24    Bastion, jump boxes, build agents
├── snet-apim        10.X.4.0/24    APIM (when needed; size /28 for stv2, /27 with reserve)
└── snet-gw          10.X.5.0/27    VPN Gateway (must be named exactly "GatewaySubnet")
```

`/24` per subnet feels generous; cheap insurance against running out and re-architecting.

NSG defaults:
- Default deny on inbound except Azure platform requirements.
- Allow only what each subnet needs (e.g. `snet-data` accepts only from `snet-compute` on private-endpoint ports).
- NSG flow logs → LA workspace.

Bicep: `bicep/modules/vnet.bicep`, `bicep/modules/nsg.bicep`.

## Hub-spoke (enterprise)

```
Hub VNet (10.0.0.0/16)
├── AzureFirewallSubnet                      Azure Firewall (Premium tier for IDPS)
├── GatewaySubnet                            VPN / ExpressRoute Gateway
├── AzureBastionSubnet                       Bastion
├── snet-shared-services 10.0.10.0/24        Private DNS, Defender, etc.
└── peered to Spokes

Spoke VNet per workload / per env (10.X.0.0/16)
├── per the default layout above
└── peered to Hub; UDR forces 0.0.0.0/0 -> Azure Firewall in Hub
```

Hub-spoke is overkill for small projects. Use when ≥ 3 workloads or compliance requires central egress inspection.

`patterns/secure-landing-zone.md` walks the full setup.

## Private endpoints - wiring it right

A PE is a NIC in your VNet that connects to a specific PaaS resource (KV vault, Storage account, SQL server, etc.). Traffic stays in the Azure backbone.

Steps:
1. **Create the PE** targeting the PaaS resource and subresource (e.g. `vault` for KV, `blob` for Storage). Bicep: `bicep/modules/private-endpoint.bicep`.
2. **Disable public network access** on the PaaS resource (turning off public access is the whole point).
3. **Private DNS zone** to resolve the private IP from your DNS server. One zone per service per VNet (or hub-shared). Common zones:
   - `privatelink.vaultcore.azure.net` (Key Vault)
   - `privatelink.blob.core.windows.net`
   - `privatelink.dfs.core.windows.net`
   - `privatelink.queue.core.windows.net`
   - `privatelink.documents.azure.com` (Cosmos)
   - `privatelink.database.windows.net` (SQL)
   - `privatelink.azurewebsites.net` (App Service / Functions)
   - `privatelink.azurecr.io` (ACR)
4. **Link the private DNS zone** to your VNet (and to the hub VNet if hub-spoke).
5. **Test** from a VM/jump box: `nslookup mykv.vault.azure.net` → must return `10.X.X.X`, not a public IP.

Pitfall: if private DNS isn't linked, apps will resolve the public name to public IP, and the PE is unused. Verify with the nslookup probe.

## VNet integration vs. private endpoint - which side is which?

- **VNet integration** (compute side): the resource gets an IP/NIC in your subnet so its egress goes through the VNet. Available on App Service P-series, Container Apps, Functions Premium/Flex, AKS.
- **Private endpoint** (data side): the PaaS resource gets a NIC in your subnet so traffic to it goes through the VNet.

Both together: compute on `snet-compute` (VNet integrated) reaches data on `snet-data` (PE'd) - fully private path.

## Common service-specific patterns

### App Service / Container Apps
- Use **VNet integration** (regional VNet integration, not the legacy point-to-site).
- Subnet must be **delegated** to the right service (`Microsoft.Web/serverFarms` or `Microsoft.App/environments`).
- All outbound calls flow through VNet → resolve private endpoints OK.
- Inbound: still public via App Service / CA endpoint, OR private via App Service Environment v3 / Container Apps internal env.

### AKS
- **Azure CNI Overlay** for new clusters (avoid kubenet legacy).
- Private cluster (`--enable-private-cluster`) for restricted API server access.
- AGIC or NGINX ingress + AGW external for HTTP.
- Workload Identity → MI per pod.

### Functions
- Premium / Flex Consumption for VNet integration.
- Consumption plan: no VNet (limitation).

### APIM
- **Internal mode**: only VNet-internal callers. Pair with App Gateway WAF in the hub for public exposure.
- **External mode** (default): public + VNet egress to backends.
- **STv2 (Stateless v2, 2024+)**: faster scale-out, recommended.

### Front Door
- Always public-facing (it's a global CDN/WAF).
- Backends can be private if you use **Private Link Service** (FD Premium feature) - backend stays VNet-only.
- Pair with App Gateway when you need region-specific routing or stateful WAF.

## Connecting to on-prem

Options (by cost ascending):
1. **Site-to-site VPN** (S2S): IPsec over internet. ~$30/mo gateway + traffic. OK to ~1 Gbps.
2. **Point-to-site VPN**: per-user laptop access. Fine for dev.
3. **ExpressRoute**: private circuit through partner. Predictable latency. From ~$300/mo (S-series) for 50 Mbps to ~$10k+ for 10 Gbps.
4. **ExpressRoute Direct**: direct fiber. Enterprise scale.

Defaults:
- VPN: BGP enabled, active-active gateway for HA.
- ExpressRoute: redundant circuits if SLA matters; FastPath enabled for low-latency apps.

Pattern: hub VNet has the gateway; spokes peer to hub and inherit transit (`UseRemoteGateway` on peering).

## Egress + DNS

Default in hub-spoke: all spoke `0.0.0.0/0` → Azure Firewall in hub via UDR. AzFW resolves DNS via Private Resolver or its own DNS proxy. No spoke-direct egress (audit visible).

For non-hub designs: enable **NAT Gateway** on the egress subnet so all outbound shares one stable IP (helpful for whitelisting at SaaS endpoints).

## DNS

In hub-spoke: **Azure Private DNS Resolver** in hub:
- Inbound endpoint: on-prem can query Azure private zones.
- Outbound endpoint + ruleset: Azure can query on-prem zones (for hybrid AD or app DNS).

In simple deployments: rely on Azure default DNS + Private DNS zones linked to VNet.

## Network security groups (NSG) sanity

- Always tag subnets and NSGs (`Project`, `Owner`, `Environment`).
- Use **Application Security Groups (ASG)** to label workloads instead of IP allowlists; rules referencing ASG self-document.
- Enable **NSG flow logs v2** + **traffic analytics**.
- Don't allow `*` in source for prod inbound rules.

## Validation probes

```bash
# DNS resolution to private IP
az network private-endpoint list -g <rg> -o table
nslookup <kv-name>.vault.azure.net   # from a VM in the VNet - must resolve to 10.x

# NSG rules on a subnet
az network vnet subnet show -g <rg> --vnet-name <vnet> -n <subnet> --query networkSecurityGroup

# Connection Monitor (proactive)
az network watcher connection-monitor create ...
```

Run these as part of `scripts/validate.sh` after every networking deploy.
