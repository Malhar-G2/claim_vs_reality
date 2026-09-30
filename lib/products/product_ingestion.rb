require "products/url_file_reader"
require "products/url_normalizer"
require "products/product_repository"

module Products
  class ProductIngestion
    def initialize(
      reader: UrlFileReader.new,
      normalizer: UrlNormalizer.new,
      repository: ProductRepository.new
    )
      @reader = reader
      @normalizer = normalizer
      @repository = repository
    end

    def ingest_file(path)
      normalized_urls = {}

      @reader.read(path).each do |url|
        normalized_urls[@normalizer.call(url)] ||= url
      end

      normalized_urls.each do |normalized_url, original_url|
        @repository.upsert_product(
          product_url: original_url,
          normalized_product_url: normalized_url,
          status: "pending_crawl"
        )
      end

      normalized_urls.length
    end
  end
end
