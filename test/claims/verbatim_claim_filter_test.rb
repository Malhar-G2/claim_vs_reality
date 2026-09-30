require "test_helper"
require "claims/verbatim_claim_filter"

class Claims::VerbatimClaimFilterTest < Minitest::Test
  def test_filter_keeps_only_claims_that_are_verbatim_substrings_of_their_source_page
    claims = [
      { claim_text: "Fast setup.", source_url: "https://vendor.example.com/pricing", impact_score: 8 },
      { claim_text: "Paraphrased setup promise", source_url: "https://vendor.example.com/pricing", impact_score: 9 }
    ]

    markdown_by_url = { "https://vendor.example.com/pricing" => "Fast setup. Works out of the box." }

    filtered = Claims::VerbatimClaimFilter.new.filter(claims: claims, markdown_by_url: markdown_by_url)

    assert_equal ["Fast setup."], filtered.map { |row| row[:claim_text] }
  end
end
