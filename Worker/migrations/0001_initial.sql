CREATE TABLE IF NOT EXISTS draws (
  id TEXT PRIMARY KEY,
  draw_number TEXT NOT NULL,
  draw_date TEXT NOT NULL,
  sales_close_at TEXT NOT NULL,
  estimated_first_prize_fund INTEGER,
  jackpot INTEGER,
  status TEXT NOT NULL,
  main_numbers TEXT NOT NULL DEFAULT '[]',
  special_number INTEGER,
  updated_at TEXT NOT NULL,
  source_url TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS draws_by_date ON draws(draw_date DESC);
