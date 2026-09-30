require "test_helper"
require "claims/responses_payload_parser"

class Claims::ResponsesPayloadParserTest < Minitest::Test
  def test_parse_extracts_claims_array_from_responses_payload
    response_json = JSON.generate({
      output: [
        {
          content: [
            {
              type: "output_text",
              text: "{\"claims\":[{\"claim_text\":\"Fast setup.\",\"source_url\":\"https://vendor.example.com/pricing\",\"impact_score\":8}]}"
            }
          ]
        }
      ]
    })

    claims = Claims::ResponsesPayloadParser.new.parse(response_json: response_json)

    assert_equal 1, claims.length
    assert_equal "Fast setup.", claims.first[:claim_text]
  end

  def test_parse_extracts_claims_from_wrapped_batch_response_payload
    response_json = JSON.generate({
      status_code: 200,
      body: {
        output: [
          {
            content: [
              {
                type: "output_text",
                text: "{\"claims\":[{\"claim_text\":\"Fast setup.\",\"source_url\":\"https://vendor.example.com/pricing\",\"impact_score\":8}]}"
              }
            ]
          }
        ]
      }
    })

    claims = Claims::ResponsesPayloadParser.new.parse(response_json: response_json)

    assert_equal 1, claims.length
    assert_equal "Fast setup.", claims.first[:claim_text]
  end
end
