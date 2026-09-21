# Claims Extractor Batch Pipeline Design

Date: 2026-09-21

## Goal

Replace the current synchronous OpenAI extraction call with an asynchronous
OpenAI Batch API pipeline using the `/v1/responses` endpoint, while keeping
the Firecrawl crawl step as the source-page ingestion stage.

The new system must:

- support thousands of product URLs
- persist state durably in a local SQLite database
- store raw OpenAI responses and final parsed claims in separate tables
- preserve the existing verbatim-claim safety check
- use small, behavior-named classes instead of large multi-purpose files
- make the database the system of record, with CSV export as a derived output

## Non-Goals

- replacing Firecrawl with another crawler
- adding a scheduler or background worker framework
- building a web UI
- shipping distributed or multi-host execution
- migrating to Postgres in this phase

## Current State

Today the pipeline is:

1. read URLs from a text file
2. fetch pages from Firecrawl
3. call OpenAI synchronously once per product
4. parse the response in-memory
5. write the final CSV

This works for small manual runs, but it does not scale cleanly to thousands
of products because:

- synchronous OpenAI calls are more expensive than Batch API calls
- state is transient and lives in process memory
- a crashed run loses progress context
- raw responses are not persisted
- output is optimized for a one-shot CSV rather than a resumable pipeline

## Chosen Approach

Use a database-backed, two-phase batch architecture:

1. ingest and crawl products into SQLite
2. generate OpenAI batch requests against `/v1/responses`
3. submit the batch input file to OpenAI
4. poll batch status later
5. import raw batch outputs into SQLite
6. parse, filter, and persist final claims into a separate table
7. optionally export claims from the database to CSV

This keeps the current Firecrawl separation, aligns with OpenAI Batch API
behavior, and provides durable restart points for large runs.

## High-Level Architecture

### Command Layer

The CLI will be split into focused commands:

- `bin/ingest_products`
  - read URLs and create/update product records
- `bin/crawl_product_pages`
  - fetch Firecrawl pages for products needing crawl results
- `bin/submit_claim_extraction_batch`
  - build JSONL, upload input file, create the OpenAI batch
- `bin/poll_claim_extraction_batch`
  - retrieve the latest batch status and persist status transitions
- `bin/import_claim_extraction_batch_results`
  - download output/error files and store raw responses
- `bin/parse_claims`
  - parse raw responses into final claims and run the verbatim check
- `bin/export_claims_csv`
  - export persisted final claims into CSV

Each command should be idempotent or near-idempotent where practical so that
reruns are safe after partial failures.

### Domain Areas

The code will be split into a few clear areas:

- `lib/database/`
  - connection management, migrations, lightweight repositories
- `lib/products/`
  - product ingestion and product state transitions
- `lib/crawling/`
  - Firecrawl integration and source page persistence
- `lib/openai_batch/`
  - request building, JSONL writing, submission, polling, file import
- `lib/claims/`
  - response parsing, verbatim filtering, final claim persistence
- `lib/export/`
  - CSV export from database records

This separation keeps class names aligned with behavior and avoids a single
provider class becoming both an API client and a workflow controller.

## Database Design

One SQLite database file will be used, with separate tables for raw outputs
and parsed claims.

Suggested location:

- `db/claims_extractor.sqlite3`

### Table: `products`

Purpose:

- one row per product URL being processed

Columns:

- `id`
- `product_url`
- `normalized_product_url`
- `status`
- `last_error`
- `created_at`
- `updated_at`

Status values:

- `pending_ingestion`
- `pending_crawl`
- `crawled`
- `pending_batch_request`
- `batched`
- `batch_completed`
- `parsed`
- `failed`

Notes:

- `normalized_product_url` lets us deduplicate repeated inputs
- `status` tracks the product-level lifecycle

### Table: `crawl_runs`

Purpose:

- group a crawl execution across many products

Columns:

- `id`
- `started_at`
- `finished_at`
- `status`
- `notes`
- `created_at`
- `updated_at`

This is optional from a purely functional perspective, but useful for
observability and replay.

### Table: `source_pages`

Purpose:

- store the Firecrawl markdown that later powers verbatim claim checking

Columns:

- `id`
- `product_id`
- `crawl_run_id`
- `source_url`
- `markdown`
- `content_sha256`
- `created_at`
- `updated_at`

Notes:

- page persistence is required because the OpenAI batch result arrives later
- `content_sha256` allows us to detect duplicate page payloads

### Table: `batch_jobs`

Purpose:

- represent one OpenAI batch job

Columns:

- `id`
- `openai_batch_id`
- `endpoint`
- `model`
- `status`
- `input_file_id`
- `output_file_id`
- `error_file_id`
- `completion_window`
- `request_total`
- `request_completed`
- `request_failed`
- `submitted_at`
- `completed_at`
- `last_polled_at`
- `created_at`
- `updated_at`

Notes:

- this stores the OpenAI batch object fields that matter operationally
- `endpoint` should be `/v1/responses`

### Table: `batch_requests`

Purpose:

- represent one request line inside a batch input file

Columns:

- `id`
- `batch_job_id`
- `product_id`
- `custom_id`
- `request_body_json`
- `status`
- `created_at`
- `updated_at`

Status values:

- `pending_submission`
- `submitted`
- `succeeded`
- `failed`

Notes:

- `custom_id` is the critical join key because OpenAI batch output lines map
  results back via `custom_id`
- `request_body_json` is persisted so the exact request sent is inspectable

### Table: `raw_model_responses`

Purpose:

- persist raw OpenAI batch outputs exactly as returned

Columns:

- `id`
- `batch_request_id`
- `response_json`
- `error_json`
- `received_at`
- `created_at`
- `updated_at`

Notes:

- one row per completed batch request
- for failed lines, `response_json` can be null and `error_json` populated

### Table: `parsed_claims`

Purpose:

- store the final extracted claims after parsing and safety filtering

Columns:

- `id`
- `product_id`
- `batch_request_id`
- `claim_text`
- `source_url`
- `impact_score`
- `passed_verbatim_check`
- `rejection_reason`
- `created_at`
- `updated_at`

Notes:

- keep rejected parsed claims too if we want auditability later
- if we want only accepted claims in this table, then create a sibling
  `parsed_claim_candidates` table; for phase one, a single table plus
  `passed_verbatim_check` is simpler

## Class Design

### Database

- `Database::ConnectionProvider`
  - opens and memoizes the SQLite connection
- `Database::Migrator`
  - creates and evolves tables

### Products

- `Products::UrlFileReader`
  - reads plain-text URL files
- `Products::ProductIngestion`
  - normalizes URLs and upserts `products`
- `Products::ProductRepository`
  - product persistence queries

### Crawling

- `Crawling::MarketingPageCrawler`
  - thin orchestration around the existing Firecrawl fetcher behavior
- `Crawling::FirecrawlPageFetcher`
  - API-facing crawler implementation, migrated from current provider
- `Crawling::SourcePageStore`
  - persists `source_pages`

`Crawling::FirecrawlPageFetcher` should remain focused on fetching remote
content. It should stop owning downstream workflow concerns.

### OpenAI Batch

- `OpenaiBatch::ResponsesRequestBuilder`
  - builds one `/v1/responses` request body for a product from source pages
- `OpenaiBatch::BatchRequestStore`
  - persists `batch_requests`
- `OpenaiBatch::JsonlBatchFileWriter`
  - writes JSONL files in the format required by the Batch API
- `OpenaiBatch::FileUploadClient`
  - uploads the JSONL file to OpenAI with the proper purpose
- `OpenaiBatch::BatchSubmissionClient`
  - creates the batch job
- `OpenaiBatch::BatchJobStore`
  - persists `batch_jobs`
- `OpenaiBatch::BatchStatusPoller`
  - retrieves batch status and updates local state
- `OpenaiBatch::BatchOutputDownloader`
  - downloads output and error files
- `OpenaiBatch::BatchResultImporter`
  - maps output lines back to `batch_requests` by `custom_id`
- `OpenaiBatch::RawModelResponseStore`
  - stores raw responses and errors

### Claims

- `Claims::ResponsesPayloadParser`
  - parses the stored raw `/v1/responses` payload into claim candidates
- `Claims::VerbatimClaimFilter`
  - compares claim text against persisted source page markdown
- `Claims::ParsedClaimStore`
  - persists final claim rows
- `Claims::ClaimExtractionResultProcessor`
  - orchestration from raw payload to parsed claim rows

### Export

- `Export::ClaimsCsvExporter`
  - exports accepted claims from SQLite to CSV

## Request Shape for `/v1/responses`

Each product will become one request line in the batch JSONL.

The request body should include:

- the chosen model
- the system prompt content from `claim_extraction_prompt.txt`
- the combined page content payload
- a structured output contract equivalent to the current schema

The batch line wrapper should contain:

- `custom_id`
- `method: "POST"`
- `url: "/v1/responses"`
- `body: { ... }`

The exact body shape should mirror current extraction behavior as closely as
possible, only changing the transport from synchronous chat completion to the
Responses API.

## Data Flow

### Phase 1: Ingest

1. read input URLs
2. normalize and upsert into `products`
3. mark uncrawled products as `pending_crawl`

### Phase 2: Crawl

1. select products with `pending_crawl`
2. fetch marketing pages through Firecrawl
3. store page markdown in `source_pages`
4. mark successful products `crawled`
5. mark failures with `last_error` and `failed`

### Phase 3: Build and Submit Batch

1. select products with `crawled`
2. load their source pages
3. build one `/v1/responses` request per product
4. persist each request in `batch_requests`
5. write JSONL lines for the batch input file
6. upload file to OpenAI
7. create batch job
8. persist `batch_jobs`
9. mark products `batched`

### Phase 4: Poll

1. retrieve batch status from OpenAI
2. update `batch_jobs`
3. when completed, capture `output_file_id` and `error_file_id`

### Phase 5: Import Raw Results

1. download output file
2. download error file if present
3. parse each line
4. resolve `custom_id` to `batch_requests`
5. store raw response/error payloads in `raw_model_responses`
6. update `batch_requests.status`
7. mark products with successful raw responses as `batch_completed`

### Phase 6: Parse Final Claims

1. load unprocessed `raw_model_responses`
2. parse claim candidates from stored payload JSON
3. run verbatim matching against `source_pages`
4. rank and trim claims per product
5. store final rows in `parsed_claims`
6. mark products `parsed`

### Phase 7: Export

1. select accepted claims from `parsed_claims`
2. write optional CSV

## Parsing and Verbatim Safety

The existing behavior should be preserved:

- claim text must come from the model output
- claims are attributed to a `source_url`
- each claim must pass a verbatim substring check against the markdown stored
  for that same source page
- ranking is based on `impact_score`
- only the top claims are exported downstream

The main change is not the business logic. The main change is that the logic
must run after raw results are persisted, not inline with the API call.

## Error Handling

### Product-Level Failures

Examples:

- Firecrawl request fails
- no pages found
- OpenAI request body cannot be built
- raw response exists but parsing fails

Handling:

- store the error on `products.last_error`
- mark the product status `failed`
- do not block the rest of the run

### Batch-Level Failures

Examples:

- input file upload fails
- batch creation fails
- batch expires
- output file retrieval fails

Handling:

- preserve `batch_jobs` status and error context
- keep already completed request results if OpenAI returned partial output
- allow rerunning import/poll commands without resubmitting already completed
  work

### Request-Level Failures

Examples:

- one `custom_id` line fails validation
- one response line returns an error

Handling:

- store error payload in `raw_model_responses.error_json`
- mark that `batch_request` as `failed`
- do not fail the entire batch import

## Scaling Considerations

The design is intentionally shaped for 1000s of products.

### Why SQLite is still acceptable here

- batch submission and result import are mostly append/update workloads
- the tool is single-user and local
- dataset size is manageable for SQLite in this phase
- operational overhead stays very low

### Constraints to respect

- do not build one giant in-memory structure for all products
- process products in chunks when crawling and when building batch files
- use page persistence so later parsing does not require re-crawling
- use one batch job for a bounded chunk size instead of “all products forever”

### Recommended chunking

Start with configurable chunk sizes:

- crawl products in groups
- build batch input files in groups

Suggested first pass:

- `CRAWL_BATCH_SIZE=100`
- `OPENAI_BATCH_REQUEST_SIZE=500`

These should be config values, not hardcoded assumptions.

## Configuration

Add environment/config support for:

- `DATABASE_URL` or `SQLITE_DB_PATH`
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `FIRECRAWL_API_KEY`
- `CRAWL_BATCH_SIZE`
- `OPENAI_BATCH_REQUEST_SIZE`
- `OPENAI_BATCH_COMPLETION_WINDOW`

Default DB path:

- `db/claims_extractor.sqlite3`

Default batch endpoint:

- `/v1/responses`

Default completion window:

- `24h`

## File Layout

Proposed layout:

- `bin/`
  - `ingest_products`
  - `crawl_product_pages`
  - `submit_claim_extraction_batch`
  - `poll_claim_extraction_batch`
  - `import_claim_extraction_batch_results`
  - `parse_claims`
  - `export_claims_csv`
- `config/`
  - `environment.rb`
- `db/`
  - `claims_extractor.sqlite3`
  - `migrations/`
- `lib/database/`
- `lib/products/`
- `lib/crawling/`
- `lib/openai_batch/`
- `lib/claims/`
- `lib/export/`

## Migration Strategy

The repo does not currently have a DB layer, so phase one should add a small,
explicit migration system instead of pulling in a large application framework.

Reasoning:

- this repo is a CLI tool, not a Rails app
- schema control is needed
- simple SQL migrations are sufficient

Implementation direction:

- create a `schema_migrations` table
- store timestamped SQL migration files under `db/migrations/`
- run them through `Database::Migrator`

## Testing Strategy

### Unit Tests

Add focused tests for:

- URL normalization
- request-body building for `/v1/responses`
- JSONL batch file formatting
- response payload parsing
- verbatim filtering logic
- ranking/top-claims logic

### Integration Tests

Add integration coverage for:

- ingest -> crawl persistence
- crawl -> batch request generation
- raw output import -> parsed claim persistence

Use stubbed Firecrawl/OpenAI payloads rather than live network calls.

### Smoke Validation

Manual smoke flow:

1. ingest a few URLs
2. crawl pages
3. submit one small batch
4. poll until complete
5. import raw responses
6. parse claims
7. export CSV from the DB

## Rollout Plan

1. add SQLite and migration support
2. persist products and source pages
3. refactor current OpenAI extractor into request-building and response-parsing
   components
4. add Batch API submission against `/v1/responses`
5. add polling and raw output import
6. add parsed claim persistence
7. add CSV export from DB
8. keep the old synchronous script temporarily until the new path is validated
9. retire the old synchronous path after verification

## Open Questions Resolved for This Design

- database: local SQLite
- persistence: one DB file, separate tables
- raw response storage: yes
- final parsed claim storage: yes
- endpoint: `/v1/responses`
- scale target: thousands of products

## Recommendation

Implement the new batch system as a database-backed pipeline, not as a patch
to the existing single-file synchronous script.

The current fetcher and claim parsing logic contain useful behavior and should
be extracted into smaller modules, but the overall operating model should
change from “run once and emit CSV” to “persist state at every stage and let
commands move products through the pipeline.”
