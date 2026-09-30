require "json"

module OpenaiBatch
  class ResponsesRequestBuilder
    PROMPT_PATH = File.expand_path("../../providers/claim_extraction_prompt.txt", __dir__)

    def build(product:, pages:)
      {
        model: ENV.fetch("OPENAI_MODEL", "gpt-4.1"),
        input: [
          {
            role: "system",
            content: [
              {
                type: "input_text",
                text: File.read(PROMPT_PATH)
              }
            ]
          },
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: combined_markdown(pages)
              }
            ]
          }
        ],
        text: {
          format: {
            type: "json_schema",
            name: "marketing_claims",
            strict: true,
            schema: response_schema
          }
        },
        metadata: {
          product_url: product.fetch("product_url")
        }
      }
    end

    private

    def combined_markdown(pages)
      pages.map do |page|
        source_url = page["source_url"] || page[:source_url] || page["url"] || page[:url]
        markdown = page["markdown"] || page[:markdown]
        "<page url=\"#{source_url}\">\n#{markdown}\n</page>"
      end.join("\n\n")
    end

    def response_schema
      {
        type: "object",
        properties: {
          claims: {
            type: "array",
            items: {
              type: "object",
              properties: {
                claim_text: { type: "string" },
                source_url: { type: "string" },
                impact_score: { type: "integer" }
              },
              required: %w[claim_text source_url impact_score],
              additionalProperties: false
            }
          }
        },
        required: ["claims"],
        additionalProperties: false
      }
    end
  end
end
