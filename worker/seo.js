/**
 * SEO monitoring — audits, snapshots, rankings (SerpAPI optional)
 */

const SEO_PREFIX = "/seo";

const SEO_KEYWORDS = [
  "junk removal toledo oh",
  "junk removal toledo",
  "same day junk removal toledo",
  "furniture removal toledo",
  "garage cleanout toledo",
  "estate cleanout toledo oh",
  "appliance removal toledo",
  "junk hauling toledo",
  "junk removal sylvania oh",
  "junk removal maumee oh",
  "junk removal perrysburg oh",
  "toledo swift haul",
];

const SEO_COMPETITORS = [
  { label: "1-800-GOT-JUNK?", domain: "1800gotjunk.com" },
  { label: "Stand Up Guys", domain: "standupguys.com" },
  { label: "College Hunks", domain: "collegehunkshaulingjunk.com" },
];

const INDEXNOW_KEY = "tsh2026toledoswiftindexnowkey01";
const SITE_URL = "https://toledoswifthaul.com";
const SITEMAP_URL = SITE_URL + "/sitemap.xml";
const MARKETING_URLS = [
  SITE_URL,
  SITE_URL + "/pages/junk-removal-sylvania-oh.html",
  SITE_URL + "/pages/junk-removal-maumee-oh.html",
  SITE_URL + "/pages/junk-removal-perrysburg-oh.html",
  SITE_URL + "/pages/junk-removal-oregon-oh.html",
  SITE_URL + "/pages/junk-removal-rossford-oh.html",
  SITE_URL + "/pages/furniture-removal-toledo.html",
  SITE_URL + "/pages/garage-cleanout-toledo.html",
  SITE_URL + "/pages/estate-cleanout-toledo.html",
  SITE_URL + "/pages/appliance-removal-toledo.html",
  SITE_URL + "/pages/junk-removal-cost-toledo.html",
];

function todayUtc() {
  return new Date().toISOString().slice(0, 10);
}

async function ensureSeoSchema(env) {
  const stmts = [
    `CREATE TABLE IF NOT EXISTS seo_sites (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      domain TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      url TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS seo_snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      site_id INTEGER NOT NULL,
      snapshot_date TEXT NOT NULL,
      health_score INTEGER NOT NULL DEFAULT 0,
      data_json TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(site_id, snapshot_date)
    )`,
    `CREATE TABLE IF NOT EXISTS seo_rankings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      site_id INTEGER NOT NULL,
      keyword TEXT NOT NULL,
      target_label TEXT NOT NULL,
      target_domain TEXT NOT NULL,
      is_competitor INTEGER NOT NULL DEFAULT 0,
      position INTEGER,
      ranking_date TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_seo_snapshots_site ON seo_snapshots(site_id, snapshot_date DESC)`,
    `CREATE INDEX IF NOT EXISTS idx_seo_rankings_site ON seo_rankings(site_id, ranking_date DESC, keyword)`,
    `CREATE TABLE IF NOT EXISTS seo_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_type TEXT NOT NULL,
      path TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_seo_events_created ON seo_events(created_at DESC)`,
  ];
  for (const sql of stmts) await env.DB.prepare(sql).run();
}

async function getOrCreateSite(env, domain, name, url) {
  let row = await env.DB.prepare("SELECT * FROM seo_sites WHERE domain = ?1").bind(domain).first();
  if (!row) {
    await env.DB.prepare(
      "INSERT INTO seo_sites (domain, name, url) VALUES (?1, ?2, ?3)"
    )
      .bind(domain, name, url)
      .run();
    row = await env.DB.prepare("SELECT * FROM seo_sites WHERE domain = ?1").bind(domain).first();
  }
  return row;
}

function extractMeta(html, name) {
  const re = new RegExp(
    `<meta[^>]+name=["']${name}["'][^>]+content=["']([^"']*)["']`,
    "i"
  );
  const m = html.match(re);
  if (m) return m[1];
  const re2 = new RegExp(
    `<meta[^>]+content=["']([^"']*)["'][^>]+name=["']${name}["']`,
    "i"
  );
  const m2 = html.match(re2);
  return m2 ? m2[1] : null;
}

function extractTitle(html) {
  const m = html.match(/<title[^>]*>([^<]*)<\/title>/i);
  return m ? m[1].trim() : null;
}

function extractH1(html) {
  const m = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  return m ? m[1].replace(/<[^>]+>/g, "").trim() : null;
}

function hasSchema(html) {
  return /application\/ld\+json/i.test(html) && /LocalBusiness/i.test(html);
}

function hasViewport(html) {
  return /name=["']viewport["']/i.test(html);
}

function auditStatus(ok, warn) {
  if (ok) return "good";
  if (warn) return "warn";
  return "bad";
}

async function runTechnicalAudit(url) {
  const start = Date.now();
  let res;
  try {
    res = await fetch(url, {
      headers: { "User-Agent": "ToledoSwiftHaul-SEO/1.0" },
      redirect: "follow",
    });
  } catch (e) {
    return {
      reachable: false,
      https: url.startsWith("https"),
      responseMs: null,
      checks: [{ id: "uptime", label: "Site reachable", status: "bad", detail: String(e.message || e) }],
      score: 0,
    };
  }

  const responseMs = Date.now() - start;
  const html = await res.text();
  const title = extractTitle(html);
  const metaDesc = extractMeta(html, "description");
  const h1 = extractH1(html);
  const schema = hasSchema(html);
  const viewport = hasViewport(html);
  const canonical = html.match(/rel=["']canonical["'][^>]+href=["']([^"']+)["']/i);

  const checks = [
    {
      id: "uptime",
      label: "Site online",
      status: res.ok ? "good" : "bad",
      detail: res.ok ? `HTTP ${res.status}` : `HTTP ${res.status}`,
    },
    {
      id: "https",
      label: "HTTPS",
      status: url.startsWith("https") && res.url.startsWith("https") ? "good" : "bad",
      detail: res.url.startsWith("https") ? "Secure connection" : "Not fully HTTPS",
    },
    {
      id: "speed",
      label: "Response time",
      status: auditStatus(responseMs < 2000, responseMs < 4000),
      detail: `${responseMs}ms`,
    },
    {
      id: "title",
      label: "Page title",
      status: auditStatus(title && title.length >= 30 && title.length <= 65, title && title.length > 0),
      detail: title ? `${title.length} chars` : "Missing",
    },
    {
      id: "meta",
      label: "Meta description",
      status: auditStatus(metaDesc && metaDesc.length >= 70 && metaDesc.length <= 160, !!metaDesc),
      detail: metaDesc ? `${metaDesc.length} chars` : "Missing",
    },
    {
      id: "h1",
      label: "H1 heading",
      status: h1 ? "good" : "bad",
      detail: h1 ? h1.slice(0, 60) : "Missing",
    },
    {
      id: "schema",
      label: "LocalBusiness schema",
      status: schema ? "good" : "warn",
      detail: schema ? "JSON-LD detected" : "Not found",
    },
    {
      id: "viewport",
      label: "Mobile viewport",
      status: viewport ? "good" : "bad",
      detail: viewport ? "Configured" : "Missing",
    },
    {
      id: "canonical",
      label: "Canonical URL",
      status: canonical ? "good" : "warn",
      detail: canonical ? "Set" : "Not found",
    },
  ];

  let score = 0;
  for (const c of checks) {
    if (c.status === "good") score += c.id === "schema" ? 15 : c.id === "speed" ? 10 : 10;
    else if (c.status === "warn") score += 5;
  }
  score = Math.min(100, score);

  return {
    reachable: res.ok,
    https: res.url.startsWith("https"),
    responseMs,
    title,
    metaDesc,
    h1,
    checks,
    score,
  };
}

async function runPageSpeed(url, apiKey) {
  if (!apiKey) return null;
  try {
    const psi = `https://pagespeedonline.googleapis.com/pagespeedonline/v5/runPagespeed?url=${encodeURIComponent(url)}&strategy=mobile&category=performance&category=seo&category=accessibility&key=${apiKey}`;
    const res = await fetch(psi);
    if (!res.ok) return null;
    const data = await res.json();
    const perf = data.lighthouseResult?.categories?.performance?.score;
    const seo = data.lighthouseResult?.categories?.seo?.score;
    const lcp = data.lighthouseResult?.audits?.["largest-contentful-paint"]?.displayValue;
    const cls = data.lighthouseResult?.audits?.["cumulative-layout-shift"]?.displayValue;
    return {
      performance: perf != null ? Math.round(perf * 100) : null,
      seo: seo != null ? Math.round(seo * 100) : null,
      lcp: lcp || null,
      cls: cls || null,
    };
  } catch {
    return null;
  }
}

async function pingSearchEngines() {
  const results = [];
  const pings = [
    { name: "google", url: `https://www.google.com/ping?sitemap=${encodeURIComponent(SITEMAP_URL)}` },
    { name: "bing", url: `https://www.bing.com/ping?sitemap=${encodeURIComponent(SITEMAP_URL)}` },
  ];
  for (const p of pings) {
    try {
      const res = await fetch(p.url, { method: "GET", redirect: "follow" });
      results.push({ engine: p.name, ok: res.ok, status: res.status });
    } catch (e) {
      results.push({ engine: p.name, ok: false, error: String(e.message || e) });
    }
  }
  return results;
}

async function submitIndexNow() {
  try {
    const body = {
      host: "toledoswifthaul.com",
      key: INDEXNOW_KEY,
      keyLocation: `${SITE_URL}/${INDEXNOW_KEY}.txt`,
      urlList: MARKETING_URLS,
    };
    const res = await fetch("https://api.indexnow.org/indexnow", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify(body),
    });
    return { ok: res.ok || res.status === 202, status: res.status };
  } catch (e) {
    return { ok: false, error: String(e.message || e) };
  }
}

async function runSeoAutomation() {
  const [pings, indexNow] = await Promise.all([pingSearchEngines(), submitIndexNow()]);
  return { pings, indexNow, at: new Date().toISOString() };
}

function serveIndexNowKey(pathname) {
  if (pathname === `/${INDEXNOW_KEY}.txt`) {
    return new Response(INDEXNOW_KEY, {
      headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=86400" },
    });
  }
  return null;
}

function domainInResult(link, domain) {
  if (!link) return false;
  try {
    const host = new URL(link).hostname.replace(/^www\./, "");
    return host === domain.replace(/^www\./, "") || host.endsWith("." + domain.replace(/^www\./, ""));
  } catch {
    return link.includes(domain);
  }
}

async function fetchSerpPosition(keyword, domain, apiKey) {
  if (!apiKey) return null;
  try {
    const q = encodeURIComponent(keyword);
    const loc = encodeURIComponent("Toledo, Ohio, United States");
    const url = `https://serpapi.com/search.json?q=${q}&location=${loc}&google_domain=google.com&gl=us&hl=en&num=20&api_key=${apiKey}`;
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = await res.json();
    const organic = data.organic_results || [];
    for (let i = 0; i < organic.length; i++) {
      if (domainInResult(organic[i].link, domain)) return i + 1;
    }
    return organic.length > 0 ? null : null;
  } catch {
    return null;
  }
}

async function handleEvent(request, env) {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    await ensureSeoSchema(env);
    const body = await request.json();
    const type = body.type || "unknown";
    const path = body.path || null;
    await env.DB.prepare(
      "INSERT INTO seo_events (event_type, path) VALUES (?1, ?2)"
    )
      .bind(type, path)
      .run();
    return json({ ok: true });
  } catch {
    return json({ ok: true });
  }
}

async function getLeadCount(env, days) {
  try {
    await ensureLeadsSchema(env);
    const since = new Date();
    since.setDate(since.getDate() - days);
    const row = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM leads WHERE created_at >= ?1"
    )
      .bind(since.toISOString())
      .first();
    return row?.c || 0;
  } catch {
    return 0;
  }
}

async function ensureLeadsSchema(env) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS leads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT NOT NULL,
      source_path TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )`
  ).run();
  await env.DB.prepare(
    `CREATE INDEX IF NOT EXISTS idx_leads_created ON leads(created_at DESC)`
  ).run();
}

async function getPhoneClickCount(env, days) {
  try {
    const since = new Date();
    since.setDate(since.getDate() - days);
    const row = await env.DB.prepare(
      "SELECT COUNT(*) AS c FROM seo_events WHERE event_type = 'phone_click' AND created_at >= ?1"
    )
      .bind(since.toISOString())
      .first();
    return row?.c || 0;
  } catch {
    return 0;
  }
}

async function getCallStats(env) {
  const week = new Date();
  week.setDate(week.getDate() - 7);
  const phoneClicksWeek = await getPhoneClickCount(env, 7);
  const formLeadsWeek = await getLeadCount(env, 7);
  const [total, weekCount] = await Promise.all([
    env.DB.prepare("SELECT COUNT(*) AS c FROM calls").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM calls WHERE created_at >= ?1")
      .bind(week.toISOString())
      .first(),
  ]);
  return { total: total?.c || 0, week: weekCount?.c || 0, phoneClicksWeek, formLeadsWeek };
}

function computeHealthScore(technical, pageSpeed, integrations) {
  let score = technical?.score || 0;
  if (pageSpeed?.performance != null) {
    score = Math.round(score * 0.6 + pageSpeed.performance * 0.25 + (pageSpeed.seo || 0) * 0.15);
  }
  if (integrations?.gsc) score = Math.min(100, score + 5);
  if (integrations?.ga4) score = Math.min(100, score + 5);
  return Math.min(100, Math.max(0, score));
}

async function runSeoSnapshot(env, site) {
  const date = todayUtc();
  const technical = await runTechnicalAudit(site.url);
  const pageSpeed = await runPageSpeed(site.url, env.PAGESPEED_API_KEY);
  const serpKey = env.SERPAPI_KEY;

  const integrations = {
    gsc: !!env.GSC_REFRESH_TOKEN,
    ga4: !!env.GA4_MEASUREMENT_ID,
    gbp: !!env.GBP_PLACE_ID,
    serpapi: !!serpKey,
    pagespeed: !!env.PAGESPEED_API_KEY,
  };

  const rankings = [];
  const keywordsToTrack = SEO_KEYWORDS.slice(0, serpKey ? SEO_KEYWORDS.length : 5);

  if (serpKey) {
    for (const kw of keywordsToTrack) {
      const pos = await fetchSerpPosition(kw, site.domain, serpKey);
      rankings.push({
        keyword: kw,
        target_label: site.name,
        target_domain: site.domain,
        is_competitor: 0,
        position: pos,
      });
      for (const comp of SEO_COMPETITORS) {
        const cpos = await fetchSerpPosition(kw, comp.domain, serpKey);
        rankings.push({
          keyword: kw,
          target_label: comp.label,
          target_domain: comp.domain,
          is_competitor: 1,
          position: cpos,
        });
      }
    }
  }

  const calls = await getCallStats(env);
  const automation = await runSeoAutomation();
  const healthScore = computeHealthScore(technical, pageSpeed, integrations);

  const snapshot = {
    date,
    healthScore,
    technical,
    pageSpeed,
    integrations,
    automation,
    calls,
    gsc: integrations.gsc
      ? { status: "connected", clicks: null, impressions: null, ctr: null, position: null }
      : {
          status: "pending",
          setup: "Add GSC service account or OAuth token to Worker secrets",
        },
    ga4: integrations.ga4
      ? { status: "connected" }
      : { status: "pending", setup: "Set GA4_MEASUREMENT_ID secret and tag on site" },
    gbp: integrations.gbp
      ? { status: "connected" }
      : { status: "pending", setup: "Claim Google Business Profile for Toledo Swift Haul" },
    keywords: keywordsToTrack,
    competitors: SEO_COMPETITORS,
  };

  await env.DB.prepare(
    `INSERT INTO seo_snapshots (site_id, snapshot_date, health_score, data_json)
     VALUES (?1, ?2, ?3, ?4)
     ON CONFLICT(site_id, snapshot_date) DO UPDATE SET
       health_score = excluded.health_score,
       data_json = excluded.data_json`
  )
    .bind(site.id, date, healthScore, JSON.stringify(snapshot))
    .run();

  if (serpKey && rankings.length) {
    await env.DB.prepare(
      "DELETE FROM seo_rankings WHERE site_id = ?1 AND ranking_date = ?2"
    )
      .bind(site.id, date)
      .run();
    for (const r of rankings) {
      await env.DB.prepare(
        `INSERT INTO seo_rankings (site_id, keyword, target_label, target_domain, is_competitor, position, ranking_date)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`
      )
        .bind(site.id, r.keyword, r.target_label, r.target_domain, r.is_competitor, r.position, date)
        .run();
    }
  }

  return snapshot;
}

async function getOverview(env, domain) {
  await ensureSeoSchema(env);
  const site = await getOrCreateSite(
    env,
    domain || "toledoswifthaul.com",
    "Toledo Swift Haul",
    "https://toledoswifthaul.com"
  );

  let snap = await env.DB.prepare(
    "SELECT * FROM seo_snapshots WHERE site_id = ?1 AND snapshot_date = ?2"
  )
    .bind(site.id, todayUtc())
    .first();

  if (!snap) {
    await runSeoSnapshot(env, site);
    snap = await env.DB.prepare(
      "SELECT * FROM seo_snapshots WHERE site_id = ?1 AND snapshot_date = ?2"
    )
      .bind(site.id, todayUtc())
      .first();
  }

  const history = await env.DB.prepare(
    "SELECT snapshot_date, health_score FROM seo_snapshots WHERE site_id = ?1 ORDER BY snapshot_date DESC LIMIT 14"
  )
    .bind(site.id)
    .all();

  const rankings = await env.DB.prepare(
    `SELECT keyword, target_label, target_domain, is_competitor, position, ranking_date
     FROM seo_rankings WHERE site_id = ?1 AND ranking_date = ?2
     ORDER BY keyword, is_competitor, position`
  )
    .bind(site.id, todayUtc())
    .all();

  const prev = history.results?.[1];
  const data = snap ? JSON.parse(snap.data_json) : null;
  const scoreDelta = prev && snap ? snap.health_score - prev.health_score : 0;

  return {
    site: { domain: site.domain, name: site.name, url: site.url },
    snapshot: data,
    healthScore: snap?.health_score || 0,
    scoreDelta,
    history: (history.results || []).reverse(),
    rankings: rankings.results || [],
    lastUpdated: snap?.created_at || null,
  };
}

async function handleSeoApi(path, method, request, env, checkAuthFn) {
  if (path === "/api/seo/overview" && method === "GET") {
    if (!checkAuthFn(request, env)) return unauthorized();
    const url = new URL(request.url);
    const domain = url.searchParams.get("domain") || "toledoswifthaul.com";
    return json(await getOverview(env, domain));
  }

  if (path === "/api/seo/refresh" && method === "POST") {
    if (!checkAuthFn(request, env)) return unauthorized();
    await ensureSeoSchema(env);
    const site = await getOrCreateSite(
      env,
      "toledoswifthaul.com",
      "Toledo Swift Haul",
      "https://toledoswifthaul.com"
    );
    const snapshot = await runSeoSnapshot(env, site);
    return json({ ok: true, healthScore: snapshot.healthScore });
  }

  return null;
}

async function runDailySeo(env) {
  await ensureSeoSchema(env);
  const site = await getOrCreateSite(
    env,
    "toledoswifthaul.com",
    "Toledo Swift Haul",
    "https://toledoswifthaul.com"
  );
  await runSeoSnapshot(env, site);
}

function isSeoDashboardRequest(url) {
  return url.pathname === SEO_PREFIX || url.pathname.startsWith(SEO_PREFIX + "/");
}

function serveSeoDashboard(pathname) {
  const files = typeof SEO_B64 !== "undefined" ? SEO_B64 : null;
  if (!files) {
    return new Response("SEO dashboard not deployed. Run deploy.ps1", { status: 503 });
  }

  let path = pathname || "/";
  if (path.startsWith(SEO_PREFIX)) {
    path = path.slice(SEO_PREFIX.length) || "/";
  }
  if (path === "/" || path === "") path = "/index.html";
  if (!path.startsWith("/")) path = "/" + path;

  const b64 = files[path] || files["/index.html"];
  if (!b64) return new Response("Not found", { status: 404 });

  const types = {
    "/index.html": "text/html; charset=utf-8",
    "/styles.css": "text/css; charset=utf-8",
    "/app.js": "application/javascript; charset=utf-8",
  };

  return new Response(decodeAsset(b64), {
    headers: {
      "Content-Type": types[path] || "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
}
