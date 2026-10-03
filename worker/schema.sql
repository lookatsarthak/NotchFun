-- NotchFun's small backend: feedback, and anonymous download and install counts.
-- Nothing here identifies a person. Visitor hashes use a salt that is thrown away
-- after a day, so the same visitor can't be followed from one day to the next.

-- One row per (day, event, channel, version, country), counting up.
CREATE TABLE IF NOT EXISTS counts (
  day     TEXT NOT NULL,
  event   TEXT NOT NULL,
  channel TEXT NOT NULL DEFAULT '',
  version TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  n       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, channel, version, country)
);

-- Today's visitor hashes, only to count unique visitors. Cleared daily.
CREATE TABLE IF NOT EXISTS visitors (
  day  TEXT NOT NULL,
  hash TEXT NOT NULL,
  PRIMARY KEY (day, hash)
);

-- Today's random salt. Yesterday's is deleted, which makes old hashes meaningless.
CREATE TABLE IF NOT EXISTS salts (
  day  TEXT PRIMARY KEY,
  salt TEXT NOT NULL
);

-- Feedback from the website and the app. Email only if the person gave one.
CREATE TABLE IF NOT EXISTS feedback (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at  TEXT NOT NULL,
  kind        TEXT NOT NULL,
  message     TEXT NOT NULL,
  email       TEXT,
  app_version TEXT,
  macos       TEXT,
  source      TEXT NOT NULL,
  emailed     INTEGER NOT NULL DEFAULT 0
);

-- Per-hour submission counts, keyed by the same daily visitor hash. Cleared daily.
CREATE TABLE IF NOT EXISTS limits (
  key  TEXT NOT NULL,
  hour TEXT NOT NULL,
  n    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (key, hour)
);

-- Daily copies of GitHub's numbers: stars, traffic (kept only 14 days by GitHub),
-- referrers, and the download count of every release file.
CREATE TABLE IF NOT EXISTS snapshots (
  day    TEXT NOT NULL,
  metric TEXT NOT NULL,
  value  INTEGER NOT NULL,
  PRIMARY KEY (day, metric)
);

-- Today's funnel per visitor hash: which steps each visit reached (bits: 1 landed,
-- 2 saw the features, 4 reached Install, 8 copied or downloaded). Rolled up into counts
-- and deleted every night, like the visitor hashes.
CREATE TABLE IF NOT EXISTS journeys (
  day   TEXT NOT NULL,
  hash  TEXT NOT NULL,
  steps INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, hash)
);

-- Maintainer sign-in by email link: one-use links (15 minutes) and the sessions they start
-- (90 days). Only hashes are stored.
CREATE TABLE IF NOT EXISTS admin_links (
  hash    TEXT PRIMARY KEY,
  expires INTEGER NOT NULL,
  used    INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS admin_sessions (
  hash    TEXT PRIMARY KEY,
  expires INTEGER NOT NULL
);
