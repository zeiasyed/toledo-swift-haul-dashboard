CREATE TABLE IF NOT EXISTS seo_sites (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  domain TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS seo_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  site_id INTEGER NOT NULL,
  snapshot_date TEXT NOT NULL,
  health_score INTEGER NOT NULL DEFAULT 0,
  data_json TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(site_id, snapshot_date),
  FOREIGN KEY (site_id) REFERENCES seo_sites(id)
);

CREATE TABLE IF NOT EXISTS seo_rankings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  site_id INTEGER NOT NULL,
  keyword TEXT NOT NULL,
  target_label TEXT NOT NULL,
  target_domain TEXT NOT NULL,
  is_competitor INTEGER NOT NULL DEFAULT 0,
  position INTEGER,
  ranking_date TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (site_id) REFERENCES seo_sites(id)
);

CREATE INDEX IF NOT EXISTS idx_seo_snapshots_site ON seo_snapshots(site_id, snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_seo_rankings_site ON seo_rankings(site_id, ranking_date DESC, keyword);

CREATE TABLE IF NOT EXISTS seo_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_type TEXT NOT NULL,
  path TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_seo_events_created ON seo_events(created_at DESC);
