require 'tty-spinner'

module ClaimExtractor
  # Thin wrapper around tty-spinner for long-running blocking calls
  # (Firecrawl crawl polling, OpenAI chat completions), so the script doesn't
  # look hung during a multi-second/minute wait with no other output.
  module Spinner
    def self.run(message)
      spinner = TTY::Spinner.new("#{message} [:spinner]", format: :dots)
      spinner.auto_spin
      result = yield
      spinner.success('(done)')
      result
    rescue StandardError
      spinner.error('(failed)')
      raise
    end
  end
end
