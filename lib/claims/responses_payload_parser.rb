require "json"

module Claims
  class ResponsesPayloadParser
    def parse(response_json:)
      payload = response_payload(JSON.parse(response_json))
      text_item = Array(payload["output"])
        .flat_map { |item| Array(item["content"]) }
        .find { |item| item["type"] == "output_text" }

      raise "Responses payload did not include output_text content" if text_item.nil?

      parsed = JSON.parse(text_item.fetch("text"))
      Array(parsed["claims"]).filter_map do |claim|
        claim_text = claim.fetch("claim_text").to_s.strip
        next if claim_text.empty?

        {
          claim_text: claim_text,
          source_url: claim.fetch("source_url").to_s.strip,
          impact_score: claim.fetch("impact_score").to_i
        }
      end
    end

    private

    def response_payload(payload)
      return payload.fetch("body") if payload.key?("body")

      payload
    end
  end
end
