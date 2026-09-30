require "csv"
require "claims/parsed_claim_repository"

module Export
  class ClaimsCsvExporter
    DEFAULT_TIME_FORMAT = "%d-%b-%Y-%H-%M-%S"

    def initialize(parsed_claim_repository: Claims::ParsedClaimRepository.new)
      @parsed_claim_repository = parsed_claim_repository
    end

    def export(path:)
      rows = @parsed_claim_repository.accepted_claims
      CSV.open(path, "w") do |csv|
        csv << %w[product_url claim_text source_url]
        rows.each do |row|
          csv << [row["product_url"], row["claim_text"], row["source_url"]]
        end
      end
      rows.length
    end

    def default_path
      "claims-#{Time.now.strftime(DEFAULT_TIME_FORMAT)}.csv"
    end
  end
end
