require "database/connection_provider"

module OpenaiBatch
  class BatchJobRepository
    TERMINAL_STATUSES = %w[completed failed expired cancelled].freeze

    def initialize(connection: Database::ConnectionProvider.new.call)
      @connection = connection
    end

    def create_from_api_response(batch_response, model:)
      timestamp = now
      counts = batch_response.fetch("request_counts", {})
      @connection.execute(
        <<~SQL,
          INSERT INTO batch_jobs(
            openai_batch_id, endpoint, model, status, input_file_id, output_file_id, error_file_id,
            completion_window, request_total, request_completed, request_failed, submitted_at, completed_at,
            last_polled_at, created_at, updated_at
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        [
          batch_response.fetch("id"),
          batch_response.fetch("endpoint"),
          model,
          batch_response.fetch("status"),
          batch_response.fetch("input_file_id"),
          batch_response["output_file_id"],
          batch_response["error_file_id"],
          batch_response.fetch("completion_window", "24h"),
          counts.fetch("total", 0),
          counts.fetch("completed", 0),
          counts.fetch("failed", 0),
          iso8601_or_now(batch_response["created_at"], timestamp),
          iso8601_or_nil(batch_response["completed_at"]),
          timestamp,
          timestamp,
          timestamp
        ]
      )
      @connection.last_insert_row_id
    end

    def non_terminal
      placeholders = TERMINAL_STATUSES.map { "?" }.join(", ")
      @connection.execute(
        "SELECT * FROM batch_jobs WHERE status NOT IN (#{placeholders}) ORDER BY id ASC",
        TERMINAL_STATUSES
      )
    end

    def update_from_api_response(batch_job_id, batch_response)
      timestamp = now
      counts = batch_response.fetch("request_counts", {})
      @connection.execute(
        <<~SQL,
          UPDATE batch_jobs
          SET status = ?, output_file_id = ?, error_file_id = ?, request_total = ?,
              request_completed = ?, request_failed = ?, completed_at = ?, last_polled_at = ?, updated_at = ?
          WHERE id = ?
        SQL
        [
          batch_response.fetch("status"),
          batch_response["output_file_id"],
          batch_response["error_file_id"],
          counts.fetch("total", 0),
          counts.fetch("completed", 0),
          counts.fetch("failed", 0),
          iso8601_or_nil(batch_response["completed_at"]),
          timestamp,
          timestamp,
          batch_job_id
        ]
      )
    end

    def find(batch_job_id)
      @connection.get_first_row("SELECT * FROM batch_jobs WHERE id = ?", [batch_job_id])
    end

    private

    def now
      Time.now.utc.iso8601
    end

    def iso8601_or_now(unix_seconds, fallback)
      return fallback if unix_seconds.nil?

      Time.at(unix_seconds).utc.iso8601
    end

    def iso8601_or_nil(unix_seconds)
      return nil if unix_seconds.nil?

      Time.at(unix_seconds).utc.iso8601
    end
  end
end
