require "test_helper"
require "products/product_ingestion"

class Products::ProductIngestionTest < Minitest::Test
  def test_ingest_file_upserts_unique_normalized_urls
    with_temp_db do
      write_temp_urls([
        "https://vendor.example.com",
        "https://vendor.example.com/",
        "https://vendor.example.com?utm_source=x"
      ])

      count = Products::ProductIngestion.new.ingest_file(@urls_path)

      assert_equal 1, count
      rows = db.execute("SELECT normalized_product_url, status FROM products")
      assert_equal [["https://vendor.example.com", "pending_crawl"]], rows.map { |row| [row["normalized_product_url"], row["status"]] }
    end
  end
end
