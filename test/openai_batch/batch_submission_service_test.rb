require "test_helper"
require "openai_batch/batch_submission_service"

class OpenaiBatch::BatchSubmissionServiceTest < Minitest::Test
  def test_submit_creates_one_batch_for_many_products
    with_temp_db do
      seed_crawled_product("https://vendor-one.example.com", "Price visibility.")
      seed_crawled_product("https://vendor-two.example.com", "Fast onboarding.")

      api_client = FakeBatchApiClient.new(
        file_id: "file-123",
        batch_response: {
          "id" => "batch-123",
          "status" => "validating",
          "input_file_id" => "file-123",
          "endpoint" => "/v1/responses",
          "completion_window" => "24h",
          "request_counts" => { "completed" => 0, "failed" => 0, "total" => 2 }
        }
      )

      count = OpenaiBatch::BatchSubmissionService.new(api_client: api_client).submit(limit: 500)

      assert_equal 2, count
      assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM batch_jobs")
      assert_equal 2, db.get_first_value("SELECT COUNT(*) FROM batch_requests")
      assert_equal 2, db.get_first_value("SELECT COUNT(*) FROM products WHERE status = 'batched'")
      assert_equal OpenaiBatch::BatchSubmissionService::MODEL, db.get_first_value("SELECT model FROM batch_jobs LIMIT 1")
      refute_empty api_client.uploaded_paths
    end
  end

  def test_submit_logs_progress_across_major_submission_stages
    with_temp_db do
      seed_crawled_product("https://vendor-one.example.com", "Price visibility.")
      logger = CapturingLogger.new

      OpenaiBatch::BatchSubmissionService.new(
        api_client: FakeBatchApiClient.new,
        logger: logger
      ).submit(limit: 500)

      assert logger.messages.any? { |message| message.include?("[BATCH_SUBMIT] loaded 1 pending products") }
      assert logger.messages.any? { |message| message.include?("[BATCH_SUBMIT] built 1 request rows") }
      assert logger.messages.any? { |message| message.include?("[BATCH_SUBMIT] wrote JSONL file") }
      assert logger.messages.any? { |message| message.include?("[BATCH_SUBMIT] persisted 1 batch requests") }
      assert logger.messages.any? { |message| message.include?("[BATCH_SUBMIT] marked 1 products as batched") }
    end
  end
end
