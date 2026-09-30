require "openai_batch/api_client"
require "openai_batch/batch_job_repository"
require "openai_batch/batch_result_importer"

module OpenaiBatch
  class BatchSyncService
    TERMINAL_STATUSES = %w[completed failed expired cancelled].freeze

    def initialize(
      api_client: ApiClient.new,
      batch_job_repository: BatchJobRepository.new,
      batch_result_importer: BatchResultImporter.new
    )
      @api_client = api_client
      @batch_job_repository = batch_job_repository
      @batch_result_importer = batch_result_importer
    end

    def sync!
      synced = 0

      @batch_job_repository.non_terminal.each do |batch_job|
        latest = @api_client.get_batch(batch_id: batch_job.fetch("openai_batch_id"))
        @batch_job_repository.update_from_api_response(batch_job.fetch("id"), latest)
        next unless TERMINAL_STATUSES.include?(latest.fetch("status"))

        refreshed_batch_job = @batch_job_repository.find(batch_job.fetch("id"))
        output_jsonl = latest["output_file_id"] ? @api_client.download_file_content(file_id: latest["output_file_id"]) : ""
        error_jsonl = latest["error_file_id"] ? @api_client.download_file_content(file_id: latest["error_file_id"]) : ""
        @batch_result_importer.import!(
          batch_job: refreshed_batch_job,
          output_jsonl: output_jsonl,
          error_jsonl: error_jsonl
        )
        synced += 1
      end

      synced
    end
  end
end
