# Dashboard deploy (Cloudflare)

## Step A — Create D1 database

1. Cloudflare dashboard → **Workers & Pages** → **D1**
2. **Create database** → name: `toledo-swift-haul-calls`
3. Open the database → **Console** → paste and run `schema.sql`

## Step B — Deploy Worker

1. **Workers & Pages** → **Create** → **Worker**
2. Name: `toledo-swift-haul-api`
3. Deploy, then **Edit code** → replace all code with `worker/index.js` from this folder
4. **Settings** → **Variables**:
   - `DASHBOARD_PASSWORD` = pick a strong password (secret)
5. **Settings** → **Bindings** → **D1** → bind `toledo-swift-haul-calls` as `DB`
6. **Triggers** → **Custom Domains** → add `api.toledoswifthaul.com`

Copy your worker URL (e.g. `https://toledo-swift-haul-api.<account>.workers.dev`).

## Step C — Deploy dashboard (Pages)

1. **Workers & Pages** → **Create** → **Pages** → **Direct Upload**
2. Project name: `toledo-swift-haul-app`
3. Upload the `dashboard/` folder
4. **Custom domains** → add `app.toledoswifthaul.com`

## Step D — DNS (Cloudflare → DNS)

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| CNAME | api | `toledo-swift-haul-api.<account>.workers.dev` | DNS only |
| CNAME | app | `toledo-swift-haul-app.pages.dev` | DNS only |

## Step E — Twilio number (567) 777-3443

**Voice → Configure:**

| Field | Value |
|-------|-------|
| A call comes in | Webhook |
| URL | `https://api.toledoswifthaul.com/voice` |
| HTTP | POST |
| Call status changes | `https://api.toledoswifthaul.com/voice/status` |
| HTTP | POST |

Save.

## Step F — Open dashboard

1. Visit `https://app.toledoswifthaul.com`
2. API URL: `https://api.toledoswifthaul.com`
3. Password: your `DASHBOARD_PASSWORD`

Test by calling **(567) 777-3443** — call should appear in dashboard within seconds.
