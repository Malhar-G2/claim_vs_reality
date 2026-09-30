require "database/connection_provider"

module OpenaiBatch
  class BatchRequestRepository
    def initialize(connection: Database::ConnectionProvider.new.call)
      @connection = connection
    end

    def build_unsaved_row(product_id:, custom_id:, request_body_json:)
      {
        product_id: product_id,
        custom_id: custom_id,
        request_body_json: request_body_json,
        status: "pending_submission"
      }
    end

    def persist_for_batch(batch_job_id:, rows:)
      timestamp = now
      rows.each do |row|
        @connection.execute(
          <<~SQL,
            INSERT INTO batch_requests(batch_job_id, product_id, custom_id, request_body_json, status, created_at, updated_at)
            VALUES(?, ?, ?, ?, ?, ?, ?)
          SQL
          [batch_job_id, row.fetch(:product_id), row.fetch(:custom_id), row.fetch(:request_body_json), "submitted", timestamp, timestamp]
        )
      end
    end

    def find_by_custom_id(batch_job_id:, custom_id:)
      @connection.get_first_row(
        "SELECT * FROM batch_requests WHERE batch_job_id = ? AND custom_id = ?",
        [batch_job_id, custom_id]
      )
    end

    def mark_succeeded(batch_request_id)
      @connection.execute(
        "UPDATE batch_requests SET status = ?, updated_at = ? WHERE id = ?",
        ["succeeded", now, batch_request_id]
      )
    end

    def mark_failed(batch_request_id)
      @connection.execute(
        "UPDATE batch_requests SET status = ?, updated_at = ? WHERE id = ?",
        ["failed", now, batch_request_id]
      )
    end

    private

    def now
      Time.now.utc.iso8601
    end
  end
end
