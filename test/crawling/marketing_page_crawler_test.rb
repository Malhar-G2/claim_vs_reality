require "test_helper"
require "crawling/marketing_page_crawler"

class Crawling::MarketingPageCrawlerTest < Minitest::Test
  def test_crawl_pending_persists_source_pages_and_marks_product_crawled
    with_temp_db do
      seed_product("https://vendor.example.com", status: "pending_crawl")
      fetcher = Minitest::Mock.new
      fetcher.expect(
        :fetch_pages,
        [{ url: "https://vendor.example.com/pricing", markdown: "Fast setup." }],
        ["https://vendor.example.com"]
      )

      count = Crawling::MarketingPageCrawler.new(fetcher: fetcher).crawl_pending(limit: 10)

      assert_equal 1, count
      assert_equal "crawled", db.get_first_value("SELECT status FROM products")
      assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM source_pages")
      fetcher.verify
    end
  end
end
