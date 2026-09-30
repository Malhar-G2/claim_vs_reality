require "json"
require "products/product_repository"
require "crawling/source_page_repository"
require "openai_batch/responses_request_builder"
require "openai_batch/jsonl_batch_file_writer"
require "openai_batch/api_client"
require "openai_batch/batch_job_repository"
require "openai_batch/batch_request_repository"
require "support/app_logger"

module OpenaiBatch
  class BatchSubmissionService
    MODEL = ENV.fetch("OPENAI_MODEL", "gpt-4.1")

    def initialize(
      product_repository: Products::ProductRepository.new,
      source_page_repository: Crawling::SourcePageRepository.new,
      request_builder: ResponsesRequestBuilder.new,
      jsonl_writer: JsonlBatchFileWriter.new,
      api_client: ApiClient.new,
      batch_job_repository: BatchJobRepository.new,
      batch_request_repository: BatchRequestRepository.new,
      logger: Support::AppLogger
    )
      @product_repository = product_repository
      @source_page_repository = source_page_repository
      @request_builder = request_builder
      @jsonl_writer = jsonl_writer
      @api_client = api_client
      @batch_job_repository = batch_job_repository
      @batch_request_repository = batch_request_repository
      @logger = logger
    end

    def submit(limit:)
      started_at = monotonic_time
      products = @product_repository.pending_batch_request(limit: limit)
      log_info("loaded #{products.length} pending products in #{elapsed_seconds(started_at)}s (limit=#{limit})")
      return 0 if products.empty?

      build_started_at = monotonic_time
      rows = products.map do |product|
        pages = @source_page_repository.for_product(product_id: product["id"])
        request_body = @request_builder.build(product: product, pages: pages)
        custom_id = "product-#{product["id"]}-#{SecureRandom.uuid}"
        @batch_request_repository.build_unsaved_row(
          product_id: product["id"],
          custom_id: custom_id,
          request_body_json: JSON.generate(request_body)
        )
      end
      log_info("built #{rows.length} request rows in #{elapsed_seconds(build_started_at)}s")

      write_started_at = monotonic_time
      jsonl_path = @jsonl_writer.write(
        requests: rows.map do |row|
          {
            custom_id: row.fetch(:custom_id),
            method: "POST",
            url: "/v1/responses",
            body: JSON.parse(row.fetch(:request_body_json))
          }
        end
      )
      log_info("wrote JSONL file path=#{jsonl_path} in #{elapsed_seconds(write_started_at)}s")

      input_file_id = @api_client.upload_batch_file(path: jsonl_path)
      batch_response = @api_client.create_batch(
        input_file_id: input_file_id,
        endpoint: "/v1/responses",
        metadata: { source: "claims_extractor" }
      )

      persist_started_at = monotonic_time
      batch_job_id = @batch_job_repository.create_from_api_response(batch_response, model: MODEL)
      @batch_request_repository.persist_for_batch(batch_job_id: batch_job_id, rows: rows)
      log_info("persisted #{rows.length} batch requests for batch_job_id=#{batch_job_id} in #{elapsed_seconds(persist_started_at)}s")

      mark_started_at = monotonic_time
      @product_repository.mark_batched(products.map { |product| product["id"] })
      log_info("marked #{products.length} products as batched in #{elapsed_seconds(mark_started_at)}s")
      products.length
    end

    private

    def log_info(message)
      @logger.info("[BATCH_SUBMIT] #{message}")
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_seconds(started_at)
      format("%.2f", monotonic_time - started_at)
    end
  end
end
