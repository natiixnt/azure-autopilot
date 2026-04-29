# Azure AI services - what to use when

## Quick chooser

| Need | Pick |
|---|---|
| LLM completions / chat | **Azure OpenAI** (GPT-5-class 2026) |
| RAG over your docs | **Azure OpenAI** + **Azure AI Search** (vector + semantic) |
| Build agent with tools + tracing | **Azure AI Foundry** (Agents) |
| Speech-to-text / TTS / translation | **Azure AI Services** (Speech) |
| OCR / form extraction | **Azure AI Document Intelligence** |
| Image classification / object detection | **Azure AI Vision** |
| Custom ML model training + deploy | **Azure Machine Learning** |
| Content safety filters | **Azure AI Content Safety** |

## Azure OpenAI

Resource type: `Microsoft.CognitiveServices/accounts` with kind `OpenAI`.

Defaults:
- **Custom subdomain** (required for AAD auth).
- **Disable public network access** + **private endpoint** for prod.
- **Managed identity** for app access (`Cognitive Services OpenAI User` role).
- **Customer-managed key** if compliance needs.
- **Diagnostic settings** to LA.
- **Region**: pick where your models are available + closest to compute. Some models region-restricted.

Model deployments:
- **Standard**: pay-per-token; throughput bursts.
- **Provisioned (PTU)**: reserved throughput; predictable latency; required for very high-load production.
- **Global Standard**: data routed to least-busy region (faster, but loses regional pinning if compliance matters).
- **Data Zone Standard**: regional residency within EU / US.

Bicep: `bicep/modules/openai.bicep`.

Pitfalls:
- Quota is per-region, per-model. Check via `az cognitiveservices usage list` before promising capacity.
- `gpt-4o-mini` not always the cheapest - measure against task; sometimes `gpt-4o` with prompt-caching wins on cost.
- Use **prompt caching** (system prompt + few-shot examples cached). Saves 50% input cost on repeated structures.
- Use **batch API** for non-realtime jobs (~50% discount).

## Azure AI Foundry (Agents + tools)

Workspace-based product for building LLM agents with:
- Tool calling, code interpreter, file search.
- Threads + run history.
- Tracing + evaluation.
- Bring-your-own data via AI Search.

Use when:
- Building an agent (multi-turn, tool-using).
- Need built-in tracing (OTel) without writing it.
- Want enterprise data grounding.

Setup via Bicep is partial - UI for some steps. Use az CLI extensions or REST.

## Azure AI Search

For RAG, full-text, vector, hybrid retrieval.

Defaults:
- **Semantic ranker** enabled.
- **Vector field** with HNSW.
- **Indexers** auto-pull from ADLS / SQL / Cosmos / SharePoint / OneLake.
- **AAD auth** with `Search Index Data Reader` / `Contributor` for indexers.
- **Private endpoint** for prod.

Tier sizing rule:
- < 2 GB index: Basic.
- 2–25 GB: Standard S1.
- > 25 GB: S2/S3 or Storage Optimized.
- Replicas for QPS, partitions for size.

Bicep: `bicep/modules/ai-search.bicep`.

## Pattern: RAG app

```
User → Container App (chat backend with MI)
                   ↓
       1. Embed query (Azure OpenAI)
       2. Search (Azure AI Search) - vector + semantic
       3. Compose prompt with retrieved docs
       4. Completion (Azure OpenAI gpt-4o-mini default; gpt-4o for high-stakes)
       5. Stream back to user
                   ↓
        App Insights traces (LangChain or Semantic Kernel auto-instrumented)
```

`patterns/ai-app.md` has the full Bicep.

## Cost control for AI

- Track token usage per user/feature (custom metric to App Insights).
- Use cheapest model that passes eval; don't default to flagship.
- Prompt caching for repeated system prompts.
- Batch API for offline jobs.
- Set quota alerts at 60/80% of provisioned capacity.
- For embeddings: `text-embedding-3-small` is good default (cheaper, fast).
