require "database/connection_provider"

module OpenaiBatch
  class RawModelResponseRepository
    def initialize(connection: Database::ConnectionProvider.new.call)
      @connection = connection
    end

    def create_success(batch_request_id:, response_json:)
      timestamp = now
      @connection.execute(
        <<~SQL,
          INSERT INTO raw_model_responses(batch_request_id, response_json, error_json, processing_state, received_at, created_at, updated_at)
          VALUES(?, ?, NULL, ?, ?, ?, ?)
          ON CONFLICT(batch_request_id)
          DO UPDATE SET response_json = excluded.response_json,
                        error_json = excluded.error_json,
                        processing_state = excluded.processing_state,
                        received_at = excluded.received_at,
                        updated_at = excluded.updated_at
        SQL
        [batch_request_id, response_json, "pending_parse", timestamp, timestamp, timestamp]
      )
    end

    def create_failure(batch_request_id:, error_json:)
      timestamp = now
      @connection.execute(
        <<~SQL,
          INSERT INTO raw_model_responses(batch_request_id, response_json, error_json, processing_state, received_at, created_at, updated_at)
          VALUES(?, NULL, ?, ?, ?, ?, ?)
          ON CONFLICT(batch_request_id)
          DO UPDATE SET response_json = excluded.response_json,
                        error_json = excluded.error_json,
                        processing_state = excluded.processing_state,
                        received_at = excluded.received_at,
                        updated_at = excluded.updated_at
        SQL
        [batch_request_id, error_json, "errored", timestamp, timestamp, timestamp]
      )
    end

    def unprocessed_successes(limit:)
      @connection.execute(
        <<~SQL,
          SELECT raw_model_responses.*, batch_requests.product_id
          FROM raw_model_responses
          INNER JOIN batch_requests ON batch_requests.id = raw_model_responses.batch_request_id
          WHERE raw_model_responses.processing_state = ?
            AND raw_model_responses.response_json IS NOT NULL
          ORDER BY raw_model_responses.id ASC
          LIMIT ?
        SQL
        ["pending_parse", limit]
      )
    end

    def mark_processed(raw_model_response_id)
      @connection.execute(
        "UPDATE raw_model_responses SET processing_state = ?, updated_at = ? WHERE id = ?",
        ["parsed", now, raw_model_response_id]
      )
    end

    private

    def now
      Time.now.utc.iso8601
    end
  end
end
