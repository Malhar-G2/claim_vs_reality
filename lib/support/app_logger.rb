module Support
  module AppLogger
    CHUNK_SIZE = 4_000
    LOGGER = Logger.new($stdout)

    def self.info(message)
      chunked(message).each { |chunk| LOGGER.info(chunk) }
    end

    def self.chunked(message)
      text = message.to_s
      return [""] if text.empty?

      text.scan(/.{1,#{CHUNK_SIZE}}/m)
    end
  end
end
