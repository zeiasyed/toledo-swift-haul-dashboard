CREATE TABLE IF NOT EXISTS calls (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  call_sid TEXT UNIQUE NOT NULL,
  from_number TEXT,
  to_number TEXT,
  status TEXT,
  direction TEXT DEFAULT 'inbound',
  duration INTEGER DEFAULT 0,
  started_at TEXT,
  ended_at TEXT,
  recording_url TEXT,
  transcription TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_calls_created ON calls(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calls_status ON calls(status);
