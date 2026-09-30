CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY,
  product_url TEXT NOT NULL,
  normalized_product_url TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS index_products_on_status ON products(status);
