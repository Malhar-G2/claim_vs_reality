# Two swappable stages:
#
#   1. A page fetcher: #fetch_pages(url) -> [{ url:, markdown: }, ...]
#      Content-fetching only, no LLM. Today: FirecrawlPageFetcher.
#
#   2. A claim extractor: #extract_claims(pages) -> [{ claim_text:, source_url: }, ...]
#      Our own LLM call over the fetched content. Today: OpenaiClaimExtractor.
#
# To swap either stage (different scraper, different LLM/provider), write a
# new class matching the relevant method signature and change the
# PAGE_FETCHER / CLAIM_EXTRACTOR constant at the top of extract_claims.rb.
# Both raise ExtractionError on failure.
module ClaimExtractor
  class ExtractionError < StandardError; end
end
