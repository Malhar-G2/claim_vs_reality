require "json"
require "net/http"
require "uri"
require "support/app_logger"

module OpenaiBatch
  class ApiClient
    BASE_URI = URI("https://api.openai.com")
    OPENAI_API_KEY = ENV.fetch("OPENAI_API_KEY")

    def initialize(logger: Support::AppLogger)
      @logger = logger
    end

    def upload_batch_file(path:)
      file_size = File.size(path)
      started_at = monotonic_time
      @logger.info("[OPENAI_BATCH_API] uploading batch file path=#{path} bytes=#{file_size}")

      uri = BASE_URI + "/v1/files"
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{OPENAI_API_KEY}"
      request.set_form(
        [
          ["purpose", "batch"],
          ["file", File.open(path, "rb"), { filename: File.basename(path), content_type: "application/jsonl" }]
        ],
        "multipart/form-data"
      )
      file_id = JSON.parse(perform(uri, request).body).fetch("id")
      @logger.info("[OPENAI_BATCH_API] uploaded batch file id=#{file_id} in #{elapsed_seconds(started_at)}s")
      file_id
    ensure
      request&.body_stream&.close if request&.body_stream.respond_to?(:close)
    end

    def create_batch(input_file_id:, endpoint:, metadata:)
      started_at = monotonic_time
      @logger.info("[OPENAI_BATCH_API] creating batch endpoint=#{endpoint} input_file_id=#{input_file_id}")
      response = post_json("/v1/batches", {
        input_file_id: input_file_id,
        endpoint: endpoint,
        completion_window: ENV.fetch("OPENAI_BATCH_COMPLETION_WINDOW", "24h"),
        metadata: metadata
      })
      @logger.info("[OPENAI_BATCH_API] created batch id=#{response.fetch("id")} status=#{response.fetch("status")} in #{elapsed_seconds(started_at)}s")
      response
    end

    def get_batch(batch_id:)
      get_json("/v1/batches/#{batch_id}")
    end

    def download_file_content(file_id:)
      uri = BASE_URI + "/v1/files/#{file_id}/content"
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{OPENAI_API_KEY}"
      perform(uri, request).body
    end

    private

    def post_json(path, body)
      uri = BASE_URI + path
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{OPENAI_API_KEY}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      JSON.parse(perform(uri, request).body)
    end

    def get_json(path)
      uri = BASE_URI + path
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{OPENAI_API_KEY}"
      JSON.parse(perform(uri, request).body)
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        response = http.request(request)
        return response if response.is_a?(Net::HTTPSuccess)

        raise "OpenAI API request failed (#{response.code}): #{response.body}"
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_seconds(started_at)
      format("%.2f", monotonic_time - started_at)
    end
  end
end
