require "json"

module OpenaiBatch
  class JsonlBatchFileWriter
    def write(requests:)
      path = File.join(Dir.tmpdir, "claims-batch-#{Time.now.to_i}-#{SecureRandom.hex(4)}.jsonl")
      File.open(path, "w") do |file|
        requests.each do |request|
          file.puts(JSON.generate(request))
        end
      end
      path
    end
  end
end
