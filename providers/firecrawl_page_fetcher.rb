require 'firecrawl'
require_relative '../spinner'

module ClaimExtractor
  # Discovers and scrapes up to MAX_PAGES marketing-relevant pages from a
  # product's homepage in one /v2/crawl call, returning each page's markdown.
  # Content-fetching only -- no LLM extraction here (see
  # OpenaiClaimExtractor for that).
  #
  # Uses includePaths/excludePaths (deterministic regex path filtering)
  # rather than /map's "search" param, which is keyword-frequency scoring on
  # the URL string only (no title/description, no semantics) and has a known
  # bug where its result limit is applied before relevance ranking runs --
  # confirmed via Firecrawl's own source (map-cosine.ts, map-utils.ts).
  #
  # onlyMainContent strips nav/header/footer from the returned markdown, but
  # does not affect which pages the crawler discovers -- confirmed via
  # Firecrawl's source: link-discovery reads the page's raw, unstripped HTML,
  # independent of the onlyMainContent output filter.
  #
  # sitemap: "skip" -- marketing pages (Pricing/Features/Product) are reached
  # via homepage nav links at depth 0-1, confirmed empirically: a head-to-head
  # test against hubspot.com found every real /products/* page (including
  # /products/marketing) via link-following alone, in well under the time a
  # sitemap-inclusive crawl took (hubspot.com's real sitemap.xml is a huge,
  # flat, unordered dump of thousands of unrelated pages -- blog posts,
  # glossary entries, videos -- and doesn't even list every product page).
  # Skipping it is both faster and at least as complete for this use case.
  #
  # Firecrawl's crawl queue has no URL-based priority/relevance scoring at
  # all (confirmed via source: job priority is only a function of a team's
  # concurrent job count, never path depth or includePaths match quality).
  # With more product-line pages existing than MAX_PAGES on a large site,
  # which ones get returned is still somewhat run-to-run variable -- there is
  # no way to force-prioritize one specific path. INCLUDE_PATHS stays narrow
  # (anchored, one-segment-deep patterns) to keep the candidate pool small
  # and raise the odds any given real product page is included.
  class FirecrawlPageFetcher
    MAX_PAGES = 30
    # Firecrawl checks the starting URL itself against includePaths -- if it
    # doesn't match, the crawl returns 0 pages. "^/?$" (empty path or bare
    # "/") keeps the homepage crawlable even though it doesn't match any
    # keyword. NOTE: a bare, unanchored "$" matches EVERY string in Ruby
    # regex (it just means "end of string") -- it is NOT "matches empty
    # string only". An earlier version of this file used bare "$" here,
    # which silently made the entire include-path filter a no-op (every
    # candidate path "matched"). Always anchor with "^" too.
    #
    # Paths are anchored ("^/pricing/?$" style, one segment deep) rather than
    # loose wildcards, so a parent marketing page isn't out-competed by its
    # own deeper subpages for the limited page slots.
    # NOTE: every pattern MUST start with "^" (anchored to the start of the
    # path). An unanchored pattern like "/marketing/?$" matches "ends with
    # /marketing" ANYWHERE in the path -- e.g. a locale-prefixed page like
    # /fi/templates/category/marketing would incorrectly match too.
    #
    # /marketing and /sales END the path (trailing "$") but do NOT restrict
    # how many segments come before the keyword -- depth was the wrong axis
    # to filter on (a legitimate content path like /a/b/marketing has the
    # same shape as a locale-prefixed duplicate like /fi/x/y/marketing; no
    # depth rule can tell them apart). The real distinguishing signal is
    # whether the first segment is a locale/language code, which is handled
    # separately below via LOCALE_PATH_PREFIX in EXCLUDE_PATHS. This mirrors
    # how canonical-tag-based dedup works industry-wide (Scrapy, Screaming
    # Frog, Crawlee): none of them do locale detection via path depth either
    # -- confirmed no crawler does hreflang/canonical-aware filtering at
    # crawl-discovery time at all (Firecrawl included); path-pattern
    # filtering pre-fetch is the realistic state of the art.
    #
    # "[\w-]*" on BOTH sides of marketing/sales allows the keyword to appear
    # anywhere within the same path segment, with other word characters or
    # hyphens before and/or after it, without allowing an actual new path
    # segment ("/") -- covers /platform/marketing-automation, /marketing-hub
    # (keyword first) AND /email-marketing (keyword last). Confirmed live:
    # both /platform/marketing-automation (activecampaign.com) and
    # /email-marketing were being missed by earlier, narrower versions of
    # this pattern.
    INCLUDE_PATHS = %w[^/?$
                      /[\w-]*marketing[\w-]*/?$
                      /[\w-]*sales[\w-]*/?$
                      ^/pricing/?$
                      ^/features/?$
                      ^/solutions?(?:/|$)
                      ^/products?/?$
                      ^/platform/?$
                      ^/(?:roi|results|impact)(?:/|$)
                      ^/testimonials?(?:/|$)].freeze

    # Full ISO 639-1 two-letter language code list, used to recognize a
    # locale-prefixed path segment (e.g. /fi/..., /sv/..., /pt-BR/...)
    # regardless of what comes after it or how deep the path goes.
    ISO_639_1_CODES = %w(
      ab aa af ak sq am ar an hy as av ae ay az bm ba eu be bn bh bi bs br bg
      my ca ch ce ny zh cv kw co cr hr cs da dv nl dz en eo et ee fo fj fi fr
      ff gl ka de el gn gu ht ha he hz hi ho hu ia id ie ga ig ik io is it iu
      ja jv kl kn kr ks kk km ki rw kv kg ko ku kj la lb lg li ln lo lt lu lv
      gv mk mg ms ml mt mi mr mh mn na nv nb nd ne ng nn no ii nr oc oj cu om
      or os pa pi fa pl ps pt qu rm rn ro ru sa sc sd se sm sg sr gd sn si sk
      sl so st es su sw ss sv ta te tg th ti bo tk tl tn to tr ts tt tw ty ug
      uk ur uz ve vi vo wa cy wo fy xh yi yo za zu
    ).freeze

    # Matches a locale-prefixed first path segment, e.g. /fi/..., /pt-BR/...
    # -- optionally followed by a region subtag (BCP 47 style: en-US, pt-BR).
    LOCALE_PATH_PREFIX = "^/(#{ISO_639_1_CODES.join('|')})(-[a-zA-Z]{2,4})?/".freeze

    EXCLUDE_PATHS = (%w(docs/.* kb/.* support/.* blog/.* careers/.*) + [LOCALE_PATH_PREFIX]).freeze

    def initialize(api_key: ENV.fetch('FIRECRAWL_API_KEY', nil))
      raise ExtractionError, 'FIRECRAWL_API_KEY is not set' if api_key.nil? || api_key.strip.empty?

      @client = Firecrawl::Client.new(api_key: api_key)
    end

    # Free-tier Firecrawl accounts are capped at a low requests/minute rate,
    # and a single crawl involves multiple internal requests (submit + several
    # polls), so this is hit routinely when processing a batch of URLs back
    # to back -- confirmed live: "Rate limit exceeded... resets at <time>".
    RATE_LIMIT_RETRIES = 5
    RATE_LIMIT_BACKOFF_SECONDS = 30

    # Returns [{ url:, markdown: }, ...] -- one entry per successfully scraped page.
    def fetch_pages(homepage_url)
      job = crawl_with_rate_limit_retry(homepage_url)
      pages = Array(job.data).filter_map { |doc| build_page(doc) }
      log_discovered_urls(pages)
      pages
    rescue Firecrawl::FirecrawlError => e
      raise ExtractionError, "Firecrawl request failed for #{homepage_url}: #{e.message}"
    end

    private

    def crawl_with_rate_limit_retry(homepage_url)
      attempts = 0

      begin
        Spinner.run("  crawling #{homepage_url}...") { @client.crawl(homepage_url, crawl_options) }
      rescue Firecrawl::RateLimitError => e
        attempts += 1
        raise if attempts > RATE_LIMIT_RETRIES

        puts "  rate limited, waiting #{RATE_LIMIT_BACKOFF_SECONDS}s before retry #{attempts}/#{RATE_LIMIT_RETRIES} (#{e.message})"
        sleep RATE_LIMIT_BACKOFF_SECONDS
        retry
      end
    end

    def crawl_options
      Firecrawl::Models::CrawlOptions.new(
        sitemap: 'skip',
        include_paths: INCLUDE_PATHS,
        exclude_paths: EXCLUDE_PATHS,
        limit: MAX_PAGES,
        # ignoreQueryParameters strips ALL query params before the
        # already-visited check -- it cannot distinguish a tracking param
        # (safe to merge) from a param that serves genuinely different
        # content (language switcher, A/B variant, pagination), confirmed
        # via Firecrawl's source (crawl-redis.ts: normalizeURL does a
        # blanket urlO.search = ""). Enabled anyway here because we verified
        # empirically (diffing scraped markdown for two ?hubs_content=...
        # variants of the same hubspot.com page) that this specific param
        # only changes outbound link tracking, not visible page content --
        # this is a per-vendor judgment call, not a universal guarantee.
        ignore_query_parameters: true,
        scrape_options: Firecrawl::Models::ScrapeOptions.new(
          formats: ['markdown'],
          only_main_content: false,
          # img tags carry no claim-relevant text but measured ~20% of a
          # real page's markdown length (mostly long asset URLs) -- pure
          # LLM token waste for this use case.
          exclude_tags: ['img']
        )
      )
    end

    def build_page(doc)
      markdown = doc.markdown.to_s
      return nil if markdown.strip.empty?
      puts "- - - - - URL: #{doc.metadata&.fetch('sourceURL', nil) || doc.metadata&.fetch('url', nil)} - - - -\n\n"
      puts "- - - - Markdown: #{markdown} - - - - \n\n"
      url = doc.metadata&.fetch('sourceURL', nil) || doc.metadata&.fetch('url', nil)
      { url: url, markdown: markdown }
    end

    def log_discovered_urls(pages)
      puts "  found #{pages.size} page(s):"
      pages.each { |page| puts "    #{page[:url]}" }
    end
  end
end
