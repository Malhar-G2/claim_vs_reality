#!/usr/bin/env ruby
# frozen_string_literal: true

warn <<~MSG
  extract_claims.rb is deprecated.

  Use the staged workflow instead:
    bundle exec ruby bin/setup_database
    bundle exec ruby bin/ingest_products <urls.txt>
    bundle exec ruby bin/crawl_product_pages
    bundle exec ruby bin/submit_claim_extraction_batch
    bundle exec ruby bin/sync_openai_batches
    bundle exec ruby bin/parse_claims
    bundle exec ruby bin/export_claims_csv [output.csv]
MSG

exit 1
