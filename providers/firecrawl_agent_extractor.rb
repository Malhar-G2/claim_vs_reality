require 'firecrawl'
require_relative '../spinner'

module ClaimExtractor
  # Comparison arm: the ORIGINAL architecture this tool started with, before
  # splitting into FirecrawlPageFetcher + OpenaiClaimExtractor. One call to
  # Firecrawl's /v2/agent (successor to /v2/extract) does page discovery,
  # scraping, AND claim extraction internally, using FIRECRAWL'S OWN LLM --
  # we supply only the prompt and schema, never see the scraped markdown,
  # and have no control over which model does the extraction or how pages
  # are discovered/prioritized.
  #
  # No verbatim check here (unlike OpenaiClaimExtractor) -- Firecrawl never
  # returns the source page content, so there is nothing to check claim_text
  # against. This is itself part of what a before/after comparison surfaces:
  # whether trusting Firecrawl's own extraction without a verbatim safety
  # net produces more paraphrased/fabricated claims than the current
  # two-stage pipeline.
  class FirecrawlAgentExtractor
    PROMPT_PATH = File.join(__dir__, 'agent_extraction_prompt.txt')
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
            required: %w(claim_text source_url impact_score)
          }
        }
      },
      required: ['claims']
    }.freeze

    def initialize(api_key: ENV.fetch('FIRECRAWL_API_KEY', nil))
      raise ExtractionError, 'FIRECRAWL_API_KEY is not set' if api_key.nil? || api_key.strip.empty?

      @client = Firecrawl::Client.new(api_key: api_key)
    end

    # Single call does fetch + extract; no separate #fetch_pages step exists
    # for this arm (unlike the current two-stage pipeline).
    #
    # Does NOT use Spinner.run here (unlike every other blocking call in this
    # codebase) -- tty-spinner correctly no-ops when stdout isn't a TTY
    # (confirmed empirically: piping a bare spinner run to a file produces
    # zero bytes), which is fine for a short call but means a run redirected
    # to a log file (e.g. via nohup, as this tool's batch scripts do) goes
    # completely silent for the FULL duration of a multi-minute agent job --
    # indistinguishable from a hung process. run_agent below prints its own
    # timestamped progress on every poll instead, so redirected/background
    # runs stay observable.
    def extract_claims(homepage_url)
      puts "  running Firecrawl agent on #{homepage_url}..."
      status = run_agent(homepage_url)
      claims = parse_claims(status)
      puts "  agent returned #{claims.size} claim(s)"
      top_claims(claims)
    end

    private

    # AGENT_TIMEOUT_SECONDS overrides the gem's DEFAULT_JOB_TIMEOUT (300s,
    # client.rb) -- that 300s is a client-side POLLING cutoff, not a real
    # Firecrawl-side limit: when it fires, the SDK raises JobTimeoutError
    # locally but the agent job keeps running server-side (confirmed via
    # gem source: #agent's poll loop just stops polling and raises; it never
    # calls #cancel_agent). Firecrawl's own docs describe agent runs as
    # legitimately taking "a few minutes," and their JS SDK ships with NO
    # default poll timeout at all for this reason -- only this Ruby gem
    # hardcodes 300s. Two real vendor URLs (etonvs.com, dayforce.com) both
    # hit exactly that 300s cutoff with zero data, which is a symptom of the
    # timeout being too short, not evidence the job was stuck or failing.
    AGENT_TIMEOUT_SECONDS = 900
    # Matches the gem's own DEFAULT_POLL_INTERVAL (client.rb) -- kept as a
    # separate constant here rather than referencing the gem's, since we're
    # reimplementing the loop ourselves (see run_agent) and want this value
    # explicit and independently changeable.
    POLL_INTERVAL_SECONDS = 2
    # How often (in elapsed seconds) to print a progress line during polling
    # -- printing every 2s (POLL_INTERVAL_SECONDS) would be noisy for a
    # 900s-cap job; this throttles it to roughly once every 30s.
    PROGRESS_LOG_INTERVAL_SECONDS = 30

    def run_agent(homepage_url)
      options = Firecrawl::Models::AgentOptions.new(
        urls: [homepage_url],
        prompt: system_prompt,
        schema: RESPONSE_SCHEMA,
        # strict_constrain_to_urls keeps the agent from wandering the whole
        # domain -- without it, `urls` is only a "constrain to" HINT to the
        # agent, not an enforced boundary (confirmed via Firecrawl's own
        # /v2/agent request schema, agentRequestSchema in
        # apps/api/src/controllers/v2/types.ts: urls has no crawl-discovery
        # semantics of its own; strictConstrainToURLs is the actual scope
        # lock). This also replaces the previous "url + /*" wildcard, which
        # is /v2/extract's documented convention (docs.firecrawl.dev/features/extract),
        # NOT /v2/agent's -- passing it here was simply a no-op path segment
        # the agent received as a literal (and likely non-existent) URL hint.
        strict_constrain_to_urls: true
      )
      status = poll_agent_with_progress(options, homepage_url)
      raise ExtractionError, "Firecrawl agent #{status.status} for #{homepage_url}" unless status.status == 'completed'

      status
    rescue Firecrawl::FirecrawlError => e
      raise ExtractionError, "Firecrawl agent request failed for #{homepage_url}: #{e.message}"
    end

    # Reimplements the gem's own #agent (start_agent + poll loop, client.rb)
    # instead of calling it directly, so we can print progress on every
    # iteration -- @client.agent(...) is an opaque blocking call with no
    # hook for observing status/elapsed time while it runs, which combined
    # with Spinner's TTY-only output (see extract_claims above) meant a
    # background/redirected run went completely silent for the entire
    # multi-minute duration of a single agent job, indistinguishable from a
    # hang. Deadline math, the done?/timeout check, and the raised error
    # (Firecrawl::JobTimeoutError, matching the gem's own class and
    # constructor args) are copied exactly from the gem's #agent so behavior
    # is unchanged other than the added logging.
    def poll_agent_with_progress(options, homepage_url)
      start = @client.start_agent(options)
      raise Firecrawl::FirecrawlError, 'Agent start did not return a job ID' if start.id.nil?

      started_at = Time.now
      deadline = started_at + AGENT_TIMEOUT_SECONDS
      last_logged_at = started_at

      while Time.now < deadline
        status = @client.get_agent_status(start.id)
        return status if status.done?

        if Time.now - last_logged_at >= PROGRESS_LOG_INTERVAL_SECONDS
          elapsed = (Time.now - started_at).round
          puts "  [agent] still running for #{homepage_url}: status=#{status.status}, elapsed=#{elapsed}s"
          last_logged_at = Time.now
        end

        sleep(POLL_INTERVAL_SECONDS)
      end

      raise Firecrawl::JobTimeoutError.new(start.id, AGENT_TIMEOUT_SECONDS, 'Agent')
    end

    def system_prompt
      File.read(PROMPT_PATH)
    end

    def parse_claims(status)
      claims = status.data&.dig('claims') || []
      claims.filter_map { |claim| build_claim(claim) }
    end

    def build_claim(claim)
      text = claim['claim_text'].to_s.strip
      return nil if text.empty?

      { claim_text: text, source_url: claim['source_url'].to_s.strip, impact_score: claim['impact_score'].to_i }
    end

    def top_claims(claims)
      claims
        .sort_by { |claim| -claim[:impact_score] }
        .first(MAX_CLAIMS)
        .map { |claim| claim.except(:impact_score) }
    end
  end
end
