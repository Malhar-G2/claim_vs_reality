module Products
  class UrlFileReader
    def read(path)
      File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)
    end
  end
end
