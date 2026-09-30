require "test_helper"
require_relative "../../providers/firecrawl_page_fetcher"

class ClaimExtractor::FirecrawlPageFetcherTest < Minitest::Test
  def test_rate_limit_backoff_seconds_uses_retry_after_hint_from_error_message
    fetcher = ClaimExtractor::FirecrawlPageFetcher.allocate

    seconds = fetcher.send(
      :rate_limit_backoff_seconds,
      "Rate limit exceeded. Please retry after 32s, resets at Thu Sep 24 2026 14:37:16 GMT+0000"
    )

    assert_equal 32, seconds
  end

  def test_rate_limit_backoff_seconds_falls_back_when_error_message_has_no_hint
    fetcher = ClaimExtractor::FirecrawlPageFetcher.allocate

    seconds = fetcher.send(:rate_limit_backoff_seconds, "Rate limit exceeded.")

    assert_equal ClaimExtractor::FirecrawlPageFetcher::RATE_LIMIT_BACKOFF_SECONDS, seconds
  end
end
