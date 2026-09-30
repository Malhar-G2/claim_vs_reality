require "database/connection_provider"

module Claims
  class ParsedClaimRepository
    def initialize(connection: Database::ConnectionProvider.new.call)
      @connection = connection
    end

    def replace_for_batch_request(product_id:, batch_request_id:, claims:)
      timestamp = now
      @connection.transaction
      @connection.execute("DELETE FROM parsed_claims WHERE batch_request_id = ?", [batch_request_id])

      claims.each do |claim|
        @connection.execute(
          <<~SQL,
            INSERT INTO parsed_claims(
              product_id, batch_request_id, claim_text, source_url, impact_score,
              passed_verbatim_check, rejection_reason, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, NULL, ?, ?)
          SQL
          [
            product_id,
            batch_request_id,
            claim.fetch(:claim_text),
            claim.fetch(:source_url),
            claim.fetch(:impact_score),
            1,
            timestamp,
            timestamp
          ]
        )
      end

      @connection.commit
    rescue StandardError
      @connection.rollback
      raise
    end

    def accepted_claims
      @connection.execute(
        <<~SQL
          SELECT products.product_url, parsed_claims.claim_text, parsed_claims.source_url, parsed_claims.impact_score
          FROM parsed_claims
          INNER JOIN products ON products.id = parsed_claims.product_id
          WHERE parsed_claims.passed_verbatim_check = 1
          ORDER BY products.id ASC, parsed_claims.id ASC
        SQL
      )
    end

    private

    def now
      Time.now.utc.iso8601
    end
  end
end
