CREATE TABLE IF NOT EXISTS batch_requests (
  id INTEGER PRIMARY KEY,
  batch_job_id INTEGER NOT NULL REFERENCES batch_jobs(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  custom_id TEXT NOT NULL UNIQUE,
  request_body_json TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS index_batch_requests_on_batch_job_id ON batch_requests(batch_job_id);
CREATE INDEX IF NOT EXISTS index_batch_requests_on_product_id ON batch_requests(product_id);
