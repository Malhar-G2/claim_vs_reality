require "test_helper"
require "openai_batch/api_client"

class OpenaiBatch::ApiClientTest < Minitest::Test
  FakeResponse = Struct.new(:body) do
    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end
  end

  class TestApiClient < OpenaiBatch::ApiClient
    attr_reader :perform_calls

    def initialize(logger:, responses:)
      super(logger: logger)
      @responses = responses
      @perform_calls = []
    end

    private

    def perform(uri, request)
      @perform_calls << { uri: uri.to_s, method: request.method }
      @responses.fetch([request.method, uri.path])
    end
  end

  def test_upload_batch_file_logs_file_size_and_uploaded_file_id
    Dir.mktmpdir do |dir|
      path = File.join(dir, "requests.jsonl")
      File.write(path, "{\"custom_id\":\"product-1\"}\n")
      logger = CapturingLogger.new
      client = TestApiClient.new(
        logger: logger,
        responses: {
          ["POST", "/v1/files"] => FakeResponse.new('{"id":"file-123"}')
        }
      )

      file_id = client.upload_batch_file(path: path)

      assert_equal "file-123", file_id
      assert logger.messages.any? { |message| message.include?("[OPENAI_BATCH_API] uploading batch file") }
      assert logger.messages.any? { |message| message.include?("bytes=") }
      assert logger.messages.any? { |message| message.include?("uploaded batch file id=file-123") }
    end
  end

  def test_create_batch_logs_endpoint_and_batch_id
    logger = CapturingLogger.new
    client = TestApiClient.new(
      logger: logger,
      responses: {
        ["POST", "/v1/batches"] => FakeResponse.new('{"id":"batch-123","status":"validating"}')
      }
    )

    response = client.create_batch(input_file_id: "file-123", endpoint: "/v1/responses", metadata: { source: "claims_extractor" })

    assert_equal "batch-123", response.fetch("id")
    assert logger.messages.any? { |message| message.include?("[OPENAI_BATCH_API] creating batch endpoint=/v1/responses input_file_id=file-123") }
    assert logger.messages.any? { |message| message.include?("[OPENAI_BATCH_API] created batch id=batch-123 status=validating") }
  end
end
