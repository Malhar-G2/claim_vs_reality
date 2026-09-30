CREATE TABLE IF NOT EXISTS source_pages (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  crawl_run_id INTEGER REFERENCES crawl_runs(id) ON DELETE SET NULL,
  source_url TEXT NOT NULL,
  markdown TEXT NOT NULL,
  content_sha256 TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS index_source_pages_on_product_id ON source_pages(product_id);
