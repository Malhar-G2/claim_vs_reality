require "products/product_repository"
require "crawling/source_page_repository"
require "openai_batch/raw_model_response_repository"
require "claims/responses_payload_parser"
require "claims/verbatim_claim_filter"
require "claims/parsed_claim_repository"

module Claims
  class ClaimParsingService
    def initialize(
      raw_model_response_repository: OpenaiBatch::RawModelResponseRepository.new,
      source_page_repository: Crawling::SourcePageRepository.new,
      responses_payload_parser: ResponsesPayloadParser.new,
      verbatim_claim_filter: VerbatimClaimFilter.new,
      parsed_claim_repository: ParsedClaimRepository.new,
      product_repository: Products::ProductRepository.new
    )
      @raw_model_response_repository = raw_model_response_repository
      @source_page_repository = source_page_repository
      @responses_payload_parser = responses_payload_parser
      @verbatim_claim_filter = verbatim_claim_filter
      @parsed_claim_repository = parsed_claim_repository
      @product_repository = product_repository
    end

    def parse_pending(limit:)
      parsed_count = 0

      @raw_model_response_repository.unprocessed_successes(limit: limit).each do |raw_response|
        claims = @responses_payload_parser.parse(response_json: raw_response.fetch("response_json"))
        markdown_by_url = @source_page_repository.markdown_by_product(product_id: raw_response.fetch("product_id"))
        filtered_claims = @verbatim_claim_filter.filter(claims: claims, markdown_by_url: markdown_by_url)
        top_claims = filtered_claims.sort_by { |claim| -claim[:impact_score] }.first(10)

        @parsed_claim_repository.replace_for_batch_request(
          product_id: raw_response.fetch("product_id"),
          batch_request_id: raw_response.fetch("batch_request_id"),
          claims: top_claims
        )
        @raw_model_response_repository.mark_processed(raw_response.fetch("id"))
        @product_repository.update_status(raw_response.fetch("product_id"), "parsed")
        parsed_count += 1
      rescue StandardError => e
        warn "Failed to parse claims for product #{raw_response.fetch("product_id")}: #{e.message}"
        @product_repository.mark_failed(raw_response.fetch("product_id"), e.message)
      end

      parsed_count
    end
  end
end
