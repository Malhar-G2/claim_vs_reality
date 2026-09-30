require "test_helper"
require "openai_batch/batch_sync_service"

class OpenaiBatch::BatchSyncServiceTest < Minitest::Test
  def test_sync_imports_ready_batch_outputs_once
    with_temp_db do
      product_id = seed_product("https://vendor.example.com", status: "batched")
      batch_job_id = seed_batch_job(openai_batch_id: "batch-123", status: "in_progress")
      seed_batch_request(batch_job_id: batch_job_id, custom_id: "product-1-abc", product_id: product_id)

      api_client = FakeBatchApiClient.new(
        batch_response: {
          "id" => "batch-123",
          "status" => "completed",
          "output_file_id" => "file-out",
          "error_file_id" => "file-err",
          "request_counts" => { "completed" => 1, "failed" => 0, "total" => 1 }
        },
        output_jsonl: %({"custom_id":"product-1-abc","response":{"status":"completed"}}),
        error_jsonl: ""
      )

      synced = OpenaiBatch::BatchSyncService.new(api_client: api_client).sync!

      assert_equal 1, synced
      assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM raw_model_responses")
      assert_equal "completed", db.get_first_value("SELECT status FROM batch_jobs WHERE id = #{batch_job_id}")
      assert_equal "succeeded", db.get_first_value("SELECT status FROM batch_requests LIMIT 1")

      synced_again = OpenaiBatch::BatchSyncService.new(api_client: api_client).sync!

      assert_equal 0, synced_again
      assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM raw_model_responses")
    end
  end
end
