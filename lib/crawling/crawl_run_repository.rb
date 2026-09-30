require "database/connection_provider"

module Crawling
  class CrawlRunRepository
    def initialize(connection: Database::ConnectionProvider.new.call)
      @connection = connection
    end

    def create_started_run
      timestamp = now
      @connection.execute(
        <<~SQL,
          INSERT INTO crawl_runs(started_at, finished_at, status, notes, created_at, updated_at)
          VALUES(?, NULL, ?, NULL, ?, ?)
        SQL
        [timestamp, "running", timestamp, timestamp]
      )
      @connection.last_insert_row_id
    end

    def finish_run(crawl_run_id, status:)
      timestamp = now
      @connection.execute(
        "UPDATE crawl_runs SET finished_at = ?, status = ?, updated_at = ? WHERE id = ?",
        [timestamp, status, timestamp, crawl_run_id]
      )
    end

    private

    def now
      Time.now.utc.iso8601
    end
  end
end
