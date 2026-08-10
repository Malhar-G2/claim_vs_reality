require 'openai'
require 'json'
require_relative '../spinner'

module ClaimExtractor
  # Takes already-fetched page markdown (from a scraping provider) and makes
  # our own LLM call to extract marketing claims -- we choose the model and
  # own the prompt, unlike a provider that does scrape+extract as one opaque
  # step. One combined call per product: all pages' markdown are concatenated
  # into a single prompt (GPT-4.1's ~1M token context window comfortably
  # fits a handful of marketing pages), with each page delimited by a
  # "### Page: <url>" marker so the model can attribute claims back to the
  # correct source_url.
  class OpenaiClaimExtractor
    MODEL = 'gpt-4.1'
    PROMPT_PATH = File.join(__dir__, 'claim_extraction_prompt.txt')
    MAX_CLAIMS = 10

    RESPONSE_SCHEMA = {
      type: 'object',
      properties: {
        claims: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              claim_text: { type: 'string' },
              source_url: { type: 'string' },
              impact_score: { type: 'integer' }
            },
            required: %w(claim_text source_url impact_score),
            additionalProperties: false
          }
        }
      },
      required: ['claims'],
      additionalProperties: false
    }.freeze

    def initialize(api_key: ENV.fetch('OPENAI_API_KEY', nil))
      raise ExtractionError, 'OPENAI_API_KEY is not set' if api_key.nil? || api_key.strip.empty?

      @client = OpenAI::Client.new(access_token: api_key)
    end

    # pages: [{ url:, markdown: }, ...] -- returns [{ claim_text:, source_url: }, ...]
    def extract_claims(pages)
      log_request(pages)
      response = Spinner.run("  waiting on #{MODEL}...") { @client.chat(parameters: request_parameters(pages)) }
      claims = parse_claims(response)
      claims = verbatim_claims(claims, pages)
      puts "  #{MODEL} returned #{claims.size} verbatim claim(s)"
      top_claims(claims)
    rescue Faraday::Error => e
      raise ExtractionError, "OpenAI request failed: #{e.message}"
    end

    private

    def request_parameters(pages)
      {
        model: MODEL,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: combined_markdown(pages) }
        ],
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'marketing_claims', strict: true, schema: RESPONSE_SCHEMA }
        }
      }
    end

    # The prompt file uses %{variable} placeholders (Ruby's `format`/`%`
    # syntax) so new variables can be added by both editing the .txt file
    # and adding a key here -- no other code changes needed. Any literal "%"
    # meant as a percent sign in the prompt text must be escaped as "%%"
    # (format's own escaping rule), same convention as this codebase's
    # in-repo counterpart (ue's judging/judge_claim_prompt.txt).
    def system_prompt
      format(File.read(PROMPT_PATH))
    end

    def combined_markdown(pages)
      pages.map { |page| "### Page: #{page[:url]}\n\n#{page[:markdown]}" }.join("\n\n---\n\n")
    end

    def log_request(pages)
      total_chars = pages.sum { |page| page[:markdown].to_s.length }
      puts "  sending #{pages.size} page(s) (~#{total_chars} chars) to #{MODEL}"
    end

    def parse_claims(response)
      content = response.dig('choices', 0, 'message', 'content')
      raise ExtractionError, "OpenAI returned no content: #{response}" if content.nil?

      claims = JSON.parse(content)['claims'] || []
      claims.filter_map { |claim| build_claim(claim) }
    rescue JSON::ParserError => e
      raise ExtractionError, "OpenAI returned invalid JSON: #{e.message}"
    end

    def build_claim(claim)
      text = claim['claim_text'].to_s.strip
      return nil if text.empty?

      { claim_text: text, source_url: claim['source_url'].to_s.strip, impact_score: claim['impact_score'].to_i }
    end

    # Prompt-level "verbatim, entire sentence" instructions are not
    # self-enforcing -- models can still paraphrase, truncate, or subtly
    # reword a claim. This mirrors ue's HandleClaimJudgment#verbatim_citations:
    # a claim is only kept if its text is an exact substring of the page it
    # claims to come from. Comparison normalizes whitespace only (markdown
    # line-wrapping can split an otherwise-intact sentence across lines),
    # never wording -- a reworded claim is dropped, not "fixed".
    def verbatim_claims(claims, pages)
      markdown_by_url = pages.each_with_object({}) { |page, h| h[page[:url]] = normalize_whitespace(page[:markdown]) }

      claims.select do |claim|
        page_text = markdown_by_url[claim[:source_url]]
        next false if page_text.nil?

        page_text.include?(normalize_whitespace(claim[:claim_text]))
      end
    end

    def normalize_whitespace(text)
      text.to_s.gsub(/[[:space:]]+/, ' ').strip
    end

    # The model scores every passing claim rather than self-truncating to
    # MAX_CLAIMS itself -- self-truncation is unverifiable from the outside
    # (we'd never see what got cut, or whether a page with only 3 good
    # claims got padded to 10 with weaker ones). Sorting and cutting off
    # here is deterministic, inspectable, and independent of prompt wording.
    # impact_score is dropped from the final result -- it exists only to
    # drive this ranking, not as an output column (CSV columns stay
    # product_url, claim_text, source_url as already agreed).
    def top_claims(claims)
      claims
        .sort_by { |claim| -claim[:impact_score] }
        .first(MAX_CLAIMS)
        .map { |claim| claim.except(:impact_score) }
    end
  end
end
