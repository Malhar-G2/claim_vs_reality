# Claims Extractor

Standalone tool for extracting vendor marketing claims at batch scale.
It now uses a local SQLite database as the system of record and OpenAI's
Batch API for asynchronous claim extraction. CSV is a derived export, not the
primary storage layer.

Not part of the `ue` Rails app. Output CSV is uploaded into the
`marketing_claims` table separately (via the admin CSV-upload panel), which
is a separate concern from this tool.

## How it works

The workflow is staged:

1. Ingest product URLs into SQLite.
2. Crawl product pages with Firecrawl and store page markdown in SQLite.
3. Build one `/v1/responses` request per product and submit many products in
   one OpenAI batch.
4. Sync pending batches later and store raw OpenAI outputs in SQLite.
5. Parse final claims from stored raw responses and persist them in SQLite.
6. Export accepted claims to CSV when needed.

One OpenAI batch contains many product requests. The local DB is the system
of record throughout the workflow.

## Setup

```
bundle install
cp .env.example .env
# edit .env and set FIRECRAWL_API_KEY and OPENAI_API_KEY
bundle exec ruby bin/setup_database
```

## Usage

Create a plain text file with one product URL per line, e.g. `urls.txt`:

```
https://vendor-one.com
https://vendor-two.com
```

### First run

If you are setting this up from scratch, run:

```
bundle exec ruby bin/setup_database
bundle exec ruby bin/ingest_products urls.txt
bundle exec ruby bin/crawl_product_pages
bundle exec ruby bin/submit_claim_extraction_batch
bundle exec ruby bin/sync_openai_batches
bundle exec ruby bin/parse_claims
bundle exec ruby bin/export_claims_csv claims.csv
```

Notes:

- `sync_openai_batches` may need to be run more than once because OpenAI batch
  processing is asynchronous.
- If the batch is still processing, wait a bit and run
  `bundle exec ruby bin/sync_openai_batches` again.
- Run `parse_claims` only after `sync_openai_batches` has imported the raw
  OpenAI response into the local DB.

### If the database is already set up

You do not need to run `bin/setup_database` again unless the schema changes.
For a normal rerun, use the same pipeline starting from ingestion:

```
bundle exec ruby bin/ingest_products urls.txt
bundle exec ruby bin/crawl_product_pages
bundle exec ruby bin/submit_claim_extraction_batch
bundle exec ruby bin/sync_openai_batches
bundle exec ruby bin/parse_claims
bundle exec ruby bin/export_claims_csv claims.csv
```

### If you are resuming an already-submitted batch

If you already ran `submit_claim_extraction_batch` earlier and only want to
finish the batch:

```
bundle exec ruby bin/sync_openai_batches
bundle exec ruby bin/parse_claims
bundle exec ruby bin/export_claims_csv claims.csv
```

Output `claims.csv` columns remain: `product_url`, `claim_text`, `source_url`.

## Internal data flow

- `products`: one row per input product URL
- `source_pages`: crawled marketing page markdown
- `batch_jobs`: one row per OpenAI batch
- `batch_requests`: one row per product request inside a batch
- `raw_model_responses`: raw stored OpenAI batch outputs
- `parsed_claims`: final persisted claims after parsing and verbatim checks

## Known limitations

- Page discovery is regex path-based (see `INCLUDE_PATHS`/`EXCLUDE_PATHS` in
  `firecrawl_page_fetcher.rb`), not semantic -- a vendor whose marketing
  pages use unconventional URL paths may be under-discovered. Refinement of
  these patterns (and the extraction prompt) is expected as this tool sees
  more real vendor sites.
- OpenAI extraction is asynchronous through the Batch API, so results are not
  available immediately after submission.
- Crawl and batch processing are resilient, but they still depend on working
  external API credentials and network access.
