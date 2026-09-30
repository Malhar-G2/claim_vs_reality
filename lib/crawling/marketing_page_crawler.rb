require "products/product_repository"
require "crawling/crawl_run_repository"
require "crawling/source_page_repository"
require "providers/firecrawl_page_fetcher"

module Crawling
  class MarketingPageCrawler
    def initialize(
      product_repository: Products::ProductRepository.new,
      crawl_run_repository: CrawlRunRepository.new,
      source_page_repository: SourcePageRepository.new,
      fetcher: ClaimExtractor::FirecrawlPageFetcher.new
    )
      @product_repository = product_repository
      @crawl_run_repository = crawl_run_repository
      @source_page_repository = source_page_repository
      @fetcher = fetcher
    end

    def crawl_pending(limit:)
      products = @product_repository.pending_crawl(limit: limit)
      return 0 if products.empty?

      crawl_run_id = @crawl_run_repository.create_started_run
      crawled_count = 0

      products.each do |product|
        pages = @fetcher.fetch_pages(product["product_url"])
        @source_page_repository.replace_for_product(
          product_id: product["id"],
          crawl_run_id: crawl_run_id,
          pages: pages
        )
        @product_repository.update_status(product["id"], "crawled")
        crawled_count += 1
      rescue StandardError => e
        warn "Failed to crawl product #{product["product_url"]}: #{e.message}"
        @product_repository.mark_failed(product["id"], e.message)
      end

      @crawl_run_repository.finish_run(crawl_run_id, status: "completed")
      crawled_count
    end
  end
end
