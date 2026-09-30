require "json"
require "openai_batch/raw_model_response_repository"
require "openai_batch/batch_request_repository"
require "products/product_repository"
require "support/app_logger"

module OpenaiBatch
  class BatchResultImporter
    def initialize(
      raw_model_response_repository: RawModelResponseRepository.new,
      batch_request_repository: BatchRequestRepository.new,
      product_repository: Products::ProductRepository.new
    )
      @raw_model_response_repository = raw_model_response_repository
      @batch_request_repository = batch_request_repository
      @product_repository = product_repository
    end

    def import!(batch_job:, output_jsonl:, error_jsonl:)
      import_output_lines(batch_job, output_jsonl)
      import_error_lines(batch_job, error_jsonl)
    end

    private

    def import_output_lines(batch_job, jsonl)
      jsonl.to_s.each_line do |line|
        next if line.strip.empty?

        payload = JSON.parse(line)
        batch_request = @batch_request_repository.find_by_custom_id(
          batch_job_id: batch_job.fetch("id"),
          custom_id: payload.fetch("custom_id")
        )
        log_openai_response(payload.fetch("response"))

        @raw_model_response_repository.create_success(
          batch_request_id: batch_request.fetch("id"),
          response_json: JSON.generate(payload.fetch("response"))
        )
        @batch_request_repository.mark_succeeded(batch_request.fetch("id"))
        @product_repository.update_status(batch_request.fetch("product_id"), "batch_completed")
      end
    end

    def import_error_lines(batch_job, jsonl)
      jsonl.to_s.each_line do |line|
        next if line.strip.empty?

        payload = JSON.parse(line)
        batch_request = @batch_request_repository.find_by_custom_id(
          batch_job_id: batch_job.fetch("id"),
          custom_id: payload.fetch("custom_id")
        )

        @raw_model_response_repository.create_failure(
          batch_request_id: batch_request.fetch("id"),
          error_json: JSON.generate(payload.fetch("error"))
        )
        @batch_request_repository.mark_failed(batch_request.fetch("id"))
        message = payload.fetch("error").fetch("message", "Batch request failed")
        warn "OpenAI batch request failed for product #{batch_request.fetch("product_id")}: #{message}"
        @product_repository.mark_failed(batch_request.fetch("product_id"), message)
      end
    end

    def log_openai_response(response_payload)
      Support::AppLogger.info("----- OpenAI response: #{JSON.generate(response_payload)}")
    end
  end
end
