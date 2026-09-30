require "database/connection_provider"

module Crawling
  class SourcePageRepository
    def initialize(connection: Database::ConnectionProvider.new.call)
      @connection = connection
    end

    def replace_for_product(product_id:, crawl_run_id:, pages:)
      timestamp = now
      @connection.transaction
      @connection.execute("DELETE FROM source_pages WHERE product_id = ?", [product_id])

      pages.each do |page|
        @connection.execute(
          <<~SQL,
            INSERT INTO source_pages(product_id, crawl_run_id, source_url, markdown, content_sha256, created_at, updated_at)
            VALUES(?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            product_id,
            crawl_run_id,
            page.fetch(:url),
            page.fetch(:markdown),
            Digest::SHA256.hexdigest(page.fetch(:markdown)),
            timestamp,
            timestamp
          ]
        )
      end
      @connection.commit
    rescue StandardError
      @connection.rollback
      raise
    end

    def for_product(product_id:)
      @connection.execute(
        "SELECT * FROM source_pages WHERE product_id = ? ORDER BY id ASC",
        [product_id]
      )
    end

    def markdown_by_product(product_id:)
      for_product(product_id: product_id).each_with_object({}) do |row, memo|
        memo[row["source_url"]] = row["markdown"]
      end
    end

    private

    def now
      Time.now.utc.iso8601
    end
  end
end
