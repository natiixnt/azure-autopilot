# Pattern: Static site / SPA

For: marketing sites, docs, simple SPAs (React/Vue/Svelte/Astro), JAMstack apps with light API.

## Architecture

```
GitHub repo → Static Web Apps (Standard) → CDN (built-in) → users
            └→ Functions (managed) for API routes
            └→ Cosmos / Storage for data
```

## Components

| Need | Pick |
|---|---|
| Static hosting + CDN | **Static Web Apps Standard** ($9/mo) |
| API | Built-in **Functions** (managed) or BYO Container App |
| Database | Cosmos DB (Static Web Apps integrates natively) |
| Auth | Built-in (Entra ID, GitHub, Twitter) or BYO |

Free tier (no API auth, no SLA): for personal/POC.
Standard tier ($9/mo): custom domain + SSL + auth + 100GB bandwidth + private endpoints + BYO Functions.

## Bicep

```bicep
module swa 'modules/static-web-app.bicep' = {
  params: {
    name: 'swa-${namePrefix}-${environment}'
    location: 'westeurope'   // SWA region != deployment region
    sku: 'Standard'
    repositoryUrl: 'https://github.com/Acme/marketing'
    branch: 'main'
    appLocation: '/'
    apiLocation: '/api'
    outputLocation: 'dist'
  }
}
```

GitHub Actions workflow auto-generated; commit to repo.

## Use cases

- Documentation sites (Docusaurus, Astro Starlight, MkDocs).
- Marketing sites with form submissions (form → Function → email).
- SPAs with light backend (auth + a few endpoints).
- Webhooks (incoming → Function).

## Skip when

- Heavy backend logic → use `webapp-saas` with Container Apps.
- WebSockets / SSE → SWA Functions limited; use Container Apps.
- Server-side rendering at scale → use Container Apps with Next.js / SvelteKit / Remix.

## Cost

- Free: $0.
- Standard: $9 + bandwidth overage.
- Enterprise: custom.
