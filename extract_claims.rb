#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'dotenv/load'
require_relative 'claim_extractor'
require_relative 'providers/firecrawl_page_fetcher'
require_relative 'providers/openai_claim_extractor'

# To swap either stage: write a new class matching the relevant contract in
# claim_extractor.rb, then change the matching constant below.
PAGE_FETCHER = ClaimExtractor::FirecrawlPageFetcher
CLAIM_EXTRACTOR = ClaimExtractor::OpenaiClaimExtractor

def read_urls(path)
  File.readlines(path).map(&:strip).reject(&:empty?)
end

def process(urls, page_fetcher, claim_extractor)
  rows = []

  urls.each do |url|
    puts "Fetching pages for #{url}..."

    begin
      pages = page_fetcher.fetch_pages(url)
      if pages.empty?
        warn "  no pages could be fetched for #{url}"
        next
      end
      puts "  fetched #{pages.size} page(s), extracting claims..."

      claims = claim_extractor.extract_claims(pages)
      if claims.empty?
        warn "  no claims found for #{url}"
      else
        claims.each { |claim| rows << claim.merge(product_url: url) }
        puts "  found #{claims.size} claim(s)"
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
  output_path = ARGV[1] || 'claims.csv'

  if input_path.nil?
    warn 'Usage: ruby extract_claims.rb <urls.txt> [output.csv]'
    exit 1
  end

  urls = read_urls(input_path)
  page_fetcher = PAGE_FETCHER.new
  claim_extractor = CLAIM_EXTRACTOR.new
  rows = process(urls, page_fetcher, claim_extractor)
  write_csv(rows, output_path)

  puts "\nWrote #{rows.size} claim(s) from #{urls.size} url(s) to #{output_path}"
end

main if __FILE__ == $PROGRAM_NAME
