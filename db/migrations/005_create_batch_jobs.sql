CREATE TABLE IF NOT EXISTS batch_jobs (
  id INTEGER PRIMARY KEY,
  openai_batch_id TEXT NOT NULL UNIQUE,
  endpoint TEXT NOT NULL,
  model TEXT NOT NULL,
  status TEXT NOT NULL,
  input_file_id TEXT NOT NULL,
  output_file_id TEXT,
  error_file_id TEXT,
  completion_window TEXT NOT NULL,
  request_total INTEGER NOT NULL DEFAULT 0,
  request_completed INTEGER NOT NULL DEFAULT 0,
  request_failed INTEGER NOT NULL DEFAULT 0,
  submitted_at TEXT NOT NULL,
  completed_at TEXT,
  last_polled_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS index_batch_jobs_on_status ON batch_jobs(status);
