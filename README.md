# Claims Extractor

Standalone tool: give it a batch of vendor product URLs, get back a CSV of
extracted marketing claims. One-off tool, run manually whenever claims need
(re)generating for a set of products -- no scheduler, no cron.

Not part of the `ue` Rails app. Output CSV is uploaded into the
`marketing_claims` table separately (via the admin CSV-upload panel), which
is a separate concern from this tool.

## How it works

Two stages, each swappable independently (see `claim_extractor.rb`):

1. **Page fetching** (`providers/firecrawl_page_fetcher.rb`): Firecrawl's
   `/v2/crawl` discovers and scrapes up to 8 marketing-relevant pages from a
   product's homepage (path-filtered to pricing/features/solutions/product
   pages, excluding docs/blog/support/careers), returning clean markdown per
   page.
2. **Claim extraction** (`providers/openai_claim_extractor.rb`): all pages'
   markdown is combined into one prompt and sent to OpenAI (GPT-4.1) with
   our own extraction prompt -- we own the model choice and prompt, not a
   third party's opaque extraction logic.

## Setup

```
bundle install
cp .env.example .env
# edit .env and set FIRECRAWL_API_KEY and OPENAI_API_KEY
```

## Usage

Create a plain text file with one product URL per line, e.g. `urls.txt`:

```
https://vendor-one.com
https://vendor-two.com
```

Then run:

```
ruby extract_claims.rb urls.txt claims.csv
```

Output `claims.csv` columns: `product_url`, `claim_text`, `source_url`.

## Swapping providers

To use a different page-fetching or claim-extraction implementation:

1. Add a new class in `providers/` matching the relevant contract in
   `claim_extractor.rb`:
   - Page fetcher: `#fetch_pages(url)` -> `[{ url:, markdown: }, ...]`
   - Claim extractor: `#extract_claims(pages)` -> `[{ claim_text:, source_url: }, ...]`
   - Raise `ClaimExtractor::ExtractionError` on failure.
2. Change the `PAGE_FETCHER` or `CLAIM_EXTRACTOR` constant at the top of
   `extract_claims.rb` to point at the new class.

Nothing else in the tool needs to change.

## Known limitations

- Page discovery is regex path-based (see `INCLUDE_PATHS`/`EXCLUDE_PATHS` in
  `firecrawl_page_fetcher.rb`), not semantic -- a vendor whose marketing
  pages use unconventional URL paths may be under-discovered. Refinement of
  these patterns (and the extraction prompt) is expected as this tool sees
  more real vendor sites.
- Capped at 8 pages per product URL.
