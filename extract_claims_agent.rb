#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'dotenv/load'
require_relative 'claim_extractor'
require_relative 'providers/firecrawl_agent_extractor'

# Ruby block-buffers $stdout by default when it isn't a TTY (e.g. redirected
# to a log file via nohup, as this tool's own batch runs do) -- without this,
# every `puts` call in this script and in FirecrawlAgentExtractor's
# poll-progress logging sits in an internal buffer and isn't actually
# written until the buffer fills or the process exits, making a real,
# multi-minute agent call look identical to a hung process from outside.
$stdout.sync = true

# Comparison arm for extract_claims.rb -- see FirecrawlAgentExtractor for
# what this architecture does differently (single Firecrawl call for
# fetch+extract, Firecrawl's own LLM, no verbatim check).
EXTRACTOR = ClaimExtractor::FirecrawlAgentExtractor

def read_urls(path)
  File.readlines(path).map(&:strip).reject(&:empty?)
end

def process(urls, extractor)
  rows = []

  urls.each do |url|
    puts "Running Firecrawl agent for #{url}..."

    begin
      claims = extractor.extract_claims(url)
      if claims.empty?
        warn "  no claims found for #{url}"
      else
        claims.each { |claim| rows << claim.merge(product_url: url) }
      end
    rescue ClaimExtractor::ExtractionError => e
      warn "  FAILED for #{url}: #{e.message}"
    end
  end

  rows
end

def write_csv(rows, path)
  CSV.open(path, 'w') do |csv|
    csv << %w(product_url claim_text source_url)
    rows.each { |row| csv << [row[:product_url], row[:claim_text], row[:source_url]] }
  end
end

def main
  input_path = ARGV[0]
  output_path = ARGV[1] || 'claims_agent.csv'

  if input_path.nil?
    warn 'Usage: ruby extract_claims_agent.rb <urls.txt> [output.csv]'
    exit 1
  end

  urls = read_urls(input_path)
  extractor = EXTRACTOR.new
  rows = process(urls, extractor)
  write_csv(rows, output_path)

  puts "\nWrote #{rows.size} claim(s) from #{urls.size} url(s) to #{output_path}"
end

main if __FILE__ == $PROGRAM_NAME
