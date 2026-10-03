-- Adds a platform (os/form, e.g. mac/desktop, ios/phone) to every count and to the daily
-- funnel, so behaviour can be compared across Mac, iPhone, Windows and so on. Run once on
-- a database created before this date; schema.sql already has it for new ones.
CREATE TABLE counts_v2 (
  day      TEXT NOT NULL,
  event    TEXT NOT NULL,
  channel  TEXT NOT NULL DEFAULT '',
  version  TEXT NOT NULL DEFAULT '',
  country  TEXT NOT NULL DEFAULT '',
  platform TEXT NOT NULL DEFAULT '',
  n        INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, channel, version, country, platform)
);
INSERT INTO counts_v2 (day, event, channel, version, country, platform, n)
  SELECT day, event, channel, version, country, '', n FROM counts;
DROP TABLE counts;
ALTER TABLE counts_v2 RENAME TO counts;
ALTER TABLE journeys ADD COLUMN platform TEXT NOT NULL DEFAULT '';
