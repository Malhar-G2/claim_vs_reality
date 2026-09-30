require "test_helper"
require "claims/claim_parsing_service"

class Claims::ClaimParsingServiceTest < Minitest::Test
  def test_parse_pending_persists_top_verbatim_claims_and_marks_product_parsed
    with_temp_db do
      product_id = seed_crawled_product("https://vendor.example.com", "Fast setup. Works out of the box.")
      db.execute("UPDATE products SET status = ? WHERE id = ?", ["batch_completed", product_id])
      batch_job_id = seed_batch_job(openai_batch_id: "batch-claims-1", status: "completed")
      batch_request_id = seed_batch_request(batch_job_id: batch_job_id, custom_id: "claim-1", product_id: product_id)
      timestamp = Time.now.utc.iso8601
      response_json = JSON.generate({
        output: [
          {
            content: [
              {
                type: "output_text",
                text: "{\"claims\":[{\"claim_text\":\"Fast setup.\",\"source_url\":\"https://vendor.example.com/pricing\",\"impact_score\":8},{\"claim_text\":\"Paraphrased promise\",\"source_url\":\"https://vendor.example.com/pricing\",\"impact_score\":9}]}"
              }
            ]
          }
        ]
      })
      db.execute(
        <<~SQL,
          INSERT INTO raw_model_responses(batch_request_id, response_json, error_json, processing_state, received_at, created_at, updated_at)
          VALUES(?, ?, NULL, ?, ?, ?, ?)
        SQL
        [batch_request_id, response_json, "pending_parse", timestamp, timestamp, timestamp]
      )

      count = Claims::ClaimParsingService.new.parse_pending(limit: 10)

      assert_equal 1, count
      assert_equal "parsed", db.get_first_value("SELECT status FROM products WHERE id = #{product_id}")
      assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM parsed_claims")
      assert_equal "Fast setup.", db.get_first_value("SELECT claim_text FROM parsed_claims")
      assert_equal "parsed", db.get_first_value("SELECT processing_state FROM raw_model_responses")
    end
  end
end
