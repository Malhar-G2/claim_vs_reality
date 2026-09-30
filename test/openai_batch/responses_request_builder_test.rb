require "test_helper"
require "openai_batch/responses_request_builder"

class OpenaiBatch::ResponsesRequestBuilderTest < Minitest::Test
  def test_build_wraps_pages_for_responses_api
    product = { "id" => 7, "product_url" => "https://vendor.example.com" }
    pages = [{ "source_url" => "https://vendor.example.com/pricing", "markdown" => "Fast setup." }]

    request = OpenaiBatch::ResponsesRequestBuilder.new.build(product: product, pages: pages)

    assert_equal ENV.fetch("OPENAI_MODEL", "gpt-4.1"), request[:model]
    assert_equal "json_schema", request[:text][:format][:type]
    assert_includes request[:input].last[:content].first[:text], "<page url=\"https://vendor.example.com/pricing\">"
  end
end
