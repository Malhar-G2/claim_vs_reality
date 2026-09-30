module Claims
  class VerbatimClaimFilter
    def filter(claims:, markdown_by_url:)
      claims.select do |claim|
        source_text = markdown_by_url[claim[:source_url]]
        next false if source_text.nil?

        normalize(source_text).include?(normalize(claim[:claim_text]))
      end
    end

    private

    def normalize(text)
      text.to_s.gsub(/[[:space:]]+/, " ").strip
    end
  end
end
