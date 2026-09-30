module Products
  class UrlNormalizer
    def call(url)
      uri = URI(url.strip)
      uri.scheme = (uri.scheme || "https").downcase
      uri.host = uri.host&.downcase
      uri.query = nil
      uri.fragment = nil

      path = uri.path.to_s
      path = "" if path == "/"
      path = path.sub(%r{/$}, "") unless path.empty?
      uri.path = path

      uri.to_s
    end
  end
end
