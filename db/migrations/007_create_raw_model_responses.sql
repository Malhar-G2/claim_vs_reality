CREATE TABLE IF NOT EXISTS raw_model_responses (
  id INTEGER PRIMARY KEY,
  batch_request_id INTEGER NOT NULL UNIQUE REFERENCES batch_requests(id) ON DELETE CASCADE,
  response_json TEXT,
  error_json TEXT,
  processing_state TEXT NOT NULL DEFAULT 'pending_parse',
  received_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS index_raw_model_responses_on_processing_state ON raw_model_responses(processing_state);
