require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../config/environment"
require "database/connection_provider"
require "database/migrator"
require "minitest/mock"

ENV["RACK_ENV"] = "test"

module TestDatabaseHelpers
  def with_temp_db
    Dir.mktmpdir do |dir|
      old_path = ENV["SQLITE_DB_PATH"]
      ENV["SQLITE_DB_PATH"] = File.join(dir, "claims.sqlite3")
      Database::Migrator.new.migrate!
      yield ENV["SQLITE_DB_PATH"]
    ensure
      ENV["SQLITE_DB_PATH"] = old_path
    end
  end

  def db
    @db ||= Database::ConnectionProvider.new.call
  end

  def reset_db_connection!
    @db&.close
    @db = nil
  end

  def write_temp_urls(urls)
    dir = Dir.mktmpdir
    @urls_path = File.join(dir, "urls.txt")
    File.write(@urls_path, urls.join("\n"))
  end

  def seed_product(url, status: "pending_crawl")
    normalized = url.sub(%r{/$}, "")
    timestamp = Time.now.utc.iso8601
    db.execute(
      <<~SQL,
        INSERT INTO products(product_url, normalized_product_url, status, last_error, created_at, updated_at)
        VALUES(?, ?, ?, NULL, ?, ?)
      SQL
      [url, normalized, status, timestamp, timestamp]
    )
    db.last_insert_row_id
  end

  def seed_crawled_product(url, markdown)
    product_id = seed_product(url, status: "crawled")
    timestamp = Time.now.utc.iso8601
    db.execute(
      <<~SQL,
        INSERT INTO source_pages(product_id, crawl_run_id, source_url, markdown, content_sha256, created_at, updated_at)
        VALUES(?, NULL, ?, ?, ?, ?, ?)
      SQL
      [product_id, "#{url}/pricing", markdown, Digest::SHA256.hexdigest(markdown), timestamp, timestamp]
    )
    product_id
  end

  def seed_batch_job(openai_batch_id:, status:, input_file_id: "file-in", output_file_id: nil, error_file_id: nil, model: "gpt-4.1", endpoint: "/v1/responses")
    timestamp = Time.now.utc.iso8601
    db.execute(
      <<~SQL,
        INSERT INTO batch_jobs(
          openai_batch_id, endpoint, model, status, input_file_id, output_file_id, error_file_id,
          completion_window, request_total, request_completed, request_failed, submitted_at, completed_at,
          last_polled_at, created_at, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?)
      SQL
      [openai_batch_id, endpoint, model, status, input_file_id, output_file_id, error_file_id, "24h", 0, 0, 0, timestamp, timestamp, timestamp]
    )
    db.last_insert_row_id
  end

  def seed_batch_request(batch_job_id:, custom_id:, product_id: seed_product("https://seeded.example.com", status: "batched"), request_body_json: "{}")
    timestamp = Time.now.utc.iso8601
    db.execute(
      <<~SQL,
        INSERT INTO batch_requests(batch_job_id, product_id, custom_id, request_body_json, status, created_at, updated_at)
        VALUES(?, ?, ?, ?, ?, ?, ?)
      SQL
      [batch_job_id, product_id, custom_id, request_body_json, "submitted", timestamp, timestamp]
    )
    db.last_insert_row_id
  end

  def seed_parsed_claim(product_url:, claim_text:, source_url:, impact_score:, passed_verbatim_check:)
    product_id = seed_product(product_url, status: "parsed")
    batch_job_id = seed_batch_job(openai_batch_id: "batch-seeded-#{product_id}", status: "completed")
    batch_request_id = seed_batch_request(batch_job_id: batch_job_id, custom_id: "claim-#{product_id}", product_id: product_id)
    timestamp = Time.now.utc.iso8601
    db.execute(
      <<~SQL,
        INSERT INTO parsed_claims(product_id, batch_request_id, claim_text, source_url, impact_score, passed_verbatim_check, rejection_reason, created_at, updated_at)
        VALUES(?, ?, ?, ?, ?, ?, NULL, ?, ?)
      SQL
      [product_id, batch_request_id, claim_text, source_url, impact_score, passed_verbatim_check ? 1 : 0, timestamp, timestamp]
    )
  end
end

class Minitest::Test
  include TestDatabaseHelpers

  def teardown
    reset_db_connection!
    super
  end
end

class CapturingLogger
  attr_reader :messages

  def initialize
    @messages = []
  end

  def info(message)
    @messages << message
  end
end

class FakeBatchApiClient
  attr_reader :uploaded_paths

  def initialize(file_id: "file-123", batch_response: nil, output_jsonl: "", error_jsonl: "")
    @file_id = file_id
    @batch_response = batch_response || {
      "id" => "batch-123",
      "status" => "validating",
      "input_file_id" => file_id,
      "endpoint" => "/v1/responses",
      "request_counts" => { "completed" => 0, "failed" => 0, "total" => 0 }
    }
    @output_jsonl = output_jsonl
    @error_jsonl = error_jsonl
    @uploaded_paths = []
  end

  def upload_batch_file(path:)
    @uploaded_paths << path
    @file_id
  end

  def create_batch(input_file_id:, endpoint:, metadata:)
    @batch_response.merge(
      "input_file_id" => input_file_id,
      "endpoint" => endpoint,
      "metadata" => metadata
    )
  end

  def get_batch(batch_id:)
    @batch_response.merge("id" => batch_id)
  end

  def download_file_content(file_id:)
    return @output_jsonl if file_id == @batch_response["output_file_id"]
    return @error_jsonl if file_id == @batch_response["error_file_id"]

    ""
  end
end
