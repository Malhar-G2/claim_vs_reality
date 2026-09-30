require "database/connection_provider"

module Products
  class ProductRepository
    def initialize(connection: Database::ConnectionProvider.new.call)
      @connection = connection
    end

    def upsert_product(product_url:, normalized_product_url:, status:)
      timestamp = now
      @connection.execute(
        <<~SQL,
          INSERT INTO products(product_url, normalized_product_url, status, last_error, created_at, updated_at)
          VALUES(?, ?, ?, NULL, ?, ?)
          ON CONFLICT(normalized_product_url)
          DO UPDATE SET product_url = excluded.product_url, updated_at = excluded.updated_at
        SQL
        [product_url, normalized_product_url, status, timestamp, timestamp]
      )
      true
    end

    def pending_crawl(limit:)
      @connection.execute(
        "SELECT * FROM products WHERE status = ? ORDER BY id ASC LIMIT ?",
        ["pending_crawl", limit]
      )
    end

    def pending_batch_request(limit:)
      @connection.execute(
        "SELECT * FROM products WHERE status = ? ORDER BY id ASC LIMIT ?",
        ["crawled", limit]
      )
    end

    def mark_batched(product_ids)
      return if product_ids.empty?

      placeholders = Array.new(product_ids.length, "?").join(", ")
      @connection.execute(
        "UPDATE products SET status = ?, updated_at = ?, last_error = NULL WHERE id IN (#{placeholders})",
        ["batched", now, *product_ids]
      )
    end

    def update_status(product_id, status)
      @connection.execute(
        "UPDATE products SET status = ?, updated_at = ?, last_error = NULL WHERE id = ?",
        [status, now, product_id]
      )
    end

    def mark_failed(product_id, error_message)
      @connection.execute(
        "UPDATE products SET status = ?, last_error = ?, updated_at = ? WHERE id = ?",
        ["failed", error_message, now, product_id]
      )
    end

    private

    def now
      Time.now.utc.iso8601
    end
  end
end
