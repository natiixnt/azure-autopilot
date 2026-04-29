# azure-autopilot

An autonomous **Azure architect + builder** skill for [Claude Code](https://docs.claude.com/en/docs/agents-and-tools/claude-code).

Takes a minimal brief from the user, autonomously picks the right architecture from a curated set of opinionated blueprints, provisions everything via `az` CLI + Bicep modules, wires identity (Entra ID + managed identity + RBAC) and networking (VNet, private endpoints, NSGs) the secure-by-default way, hooks observability + cost controls automatically, and emits precise click-by-click walkthroughs for the few UI-only steps.

## What's inside

| | |
|---|---|
| **References** (13) | architecture decisions, compute / data / networking / identity / messaging / AI services / observability / security / cost-control / DevOps / Bicep syntax / troubleshooting |
| **Patterns** (6 blueprints) | webapp-saas, ai-app (RAG/agent/chatbot), data-platform (Fabric), api-microservices, secure-landing-zone (CAF), static-site |
| **Bicep modules** (18) | log-analytics, app-insights, managed-identity, role-assignment, key-vault, vnet, storage, container-apps-env, container-app, acr, postgres-flexible, sql-server, cosmos, redis, service-bus, front-door, openai, ai-search, budget, action-group + `main.bicep` orchestrator |
| **Scripts** (6) | `auth.sh`, `provision.sh`, `validate.sh`, `identity.py`, `cost-report.sh`, `inventory.sh` |
| **Workflows** (4) | new-app-from-zero, audit-existing-subscription, cost-optimization, security-hardening |
| **UI walkthroughs** (2) | subscription + management group setup, Conditional Access |
| **Templates** | `.env.example`, naming convention, tagging policy, 3 Azure Policy JSONs (require-tags, allowed-locations, https-only-storage), GitHub Actions OIDC workflows |

Total: ~7100 lines across 60+ files.

## Operating principles (the defaults the skill enforces)

1. **Pattern first, services second** - ask what you're building, map to a blueprint.
2. **Bicep is the IaC default** - Terraform only if you already have a TF estate.
3. **Identity-first design** - managed identity everywhere; no client secrets in app config; RBAC at the resource level.
4. **Private by default for prod** - private endpoints + VNet integration on data plane.
5. **Observability is not optional** - one Log Analytics workspace per environment; App Insights wired into compute; diagnostic settings on every resource.
6. **Cost controls before resources** - tags policy, budgets at 50/80/100%, dev/test SKUs in non-prod.
7. **Probe before claiming success** - every step has a validation.
8. **Reversible by default** - `az deployment group what-if` before every Bicep deploy.

## Install

This skill goes into your local Claude Code config under `~/.claude/skills/`.

### Option A - clone directly

```bash
git clone https://github.com/<org>/azure-autopilot.git \
    ~/.claude/skills/azure-autopilot
```

That's it. Restart Claude Code (or start a new session) and the skill auto-registers.

### Option B - fork + symlink (if you want to track upstream + keep local edits)

```bash
git clone https://github.com/<your-fork>/azure-autopilot.git ~/code/azure-autopilot
ln -s ~/code/azure-autopilot ~/.claude/skills/azure-autopilot
```

### Verify it loaded

In Claude Code, ask: *"What Azure skills do you have?"* - Claude should list `azure-autopilot` among the available skills.

The skill activates automatically when you mention Azure, Bicep, App Service, Container Apps, Cosmos, Entra ID, etc. No `/command` needed.

## Prerequisites for the **target machine** that will run the skill's outputs

The skill itself has no runtime - it produces Bicep + scripts that you run. To execute the produced artifacts you need:

| Tool | Why | Install |
|---|---|---|
| Azure CLI (`az`) | All provisioning | https://learn.microsoft.com/cli/azure/install-azure-cli |
| Bicep | IaC | `az bicep install` (auto on first use) |
| Python 3.10+ | `scripts/identity.py` + dev | system python ok |
| Bash | `scripts/*.sh` | system shell |
| `gh` (optional) | GitHub Actions OIDC setup | https://cli.github.com/ |
| Owner/Contributor on target Azure subscription | Provisioning | grant via your tenant admin |

The skill checks all of these via `auth.sh probe` before it does anything destructive.

## Quick start

```bash
# In Claude Code
> Build me a SaaS web app on Azure for a CRM consultancy. ~20 internal users, 
  Postgres backend, custom domain, GDPR-compliant region.
```

The skill will:
1. Ask 5–10 discovery questions (audience, region, integrations, budget, CI/CD).
2. Render a mermaid architecture and wait for your OK.
3. Walk Azure AD app registration + tenant settings (UI walkthroughs).
4. Generate `bicep/main.bicep` + `bicep/parameters/{dev,test,prod}.bicepparam` from the `webapp-saas` pattern.
5. Run `bash scripts/auth.sh probe` + `bash scripts/provision.sh dev` (with `what-if` first).
6. Validate with `bash scripts/validate.sh dev`.
7. Wire GitHub Actions OIDC + the supplied workflows.
8. Hand over with a punch-list of what's done and what needs a human.

## Tested patterns

- **`patterns/webapp-saas.md`** - public web app + Postgres + KV + Front Door + GitHub Actions
- **`patterns/ai-app.md`** - chatbot / RAG / agent (Azure OpenAI + AI Search + Cosmos)
- **`patterns/data-platform.md`** - Fabric lakehouse + warehouse + Power BI semantic model
- **`patterns/api-microservices.md`** - APIM + Container Apps + Service Bus polyglot
- **`patterns/secure-landing-zone.md`** - CAF MG hierarchy + hub-spoke + Defender + Sentinel
- **`patterns/static-site.md`** - Static Web Apps + Functions

## How Claude Code skills work (1-minute primer)

A skill is a folder with a `SKILL.md` whose frontmatter contains a `description` of when it activates. When the user says something matching the description, Claude reads `SKILL.md` and follows its operating instructions; it can then load referenced files (`references/`, `patterns/`, `scripts/`, etc.) on demand.

You don't need to invoke the skill - Claude finds it automatically. To force-list available skills: ask *"what skills are loaded?"* in Claude Code.

Skill location resolution order:
- Project-local: `<repo>/.claude/skills/<name>/SKILL.md`
- User-global: `~/.claude/skills/<name>/SKILL.md`
- Plugin-installed: managed by Claude Code

## Companion skills

This skill is part of a Microsoft-stack autopilot family:

- **azure-autopilot** (this) - Azure infra
- **powerbi-implementation** - Power BI / Fabric semantic models, RLS, deployment pipelines, embedding ([install separately](#))

The two cross-reference: `patterns/data-platform.md` here points to `powerbi-implementation` for the BI consumption layer.

## Contributing

Issues + PRs welcome. The skill grows organically - add new modules to `bicep/modules/` when you find a missing service, add new patterns when a recurring architecture shows up, add new workflows for end-to-end recipes.

When adding a Bicep module:
- Follow the existing shape: `name`, `location`, `tags`, then service-specific params.
- Default to least-privilege + private-by-default + AAD-only auth.
- Always add diagnostic settings (optional via `workspaceId` param).
- Output `id`, `name`, and any FQDN/endpoint the consumer will need.

## License

MIT - see [LICENSE](LICENSE).

## Disclaimer

This skill produces Bicep + shell scripts that provision Azure resources. **Always run `az deployment group what-if` and read the diff before applying.** The skill enforces this in `provision.sh`, but the decision to apply remains yours. Costs incurred on Azure are your responsibility; review the SKU + budget defaults in the parameter files.
