CREATE TABLE IF NOT EXISTS parsed_claims (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  batch_request_id INTEGER NOT NULL REFERENCES batch_requests(id) ON DELETE CASCADE,
  claim_text TEXT NOT NULL,
  source_url TEXT NOT NULL,
  impact_score INTEGER NOT NULL,
  passed_verbatim_check INTEGER NOT NULL,
  rejection_reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS index_parsed_claims_on_product_id ON parsed_claims(product_id);
CREATE INDEX IF NOT EXISTS index_parsed_claims_on_batch_request_id ON parsed_claims(batch_request_id);
