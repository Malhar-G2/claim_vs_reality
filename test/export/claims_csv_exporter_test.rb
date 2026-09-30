require "test_helper"
require "export/claims_csv_exporter"

class Export::ClaimsCsvExporterTest < Minitest::Test
  def test_export_writes_only_accepted_claims
    with_temp_db do
      seed_parsed_claim(
        product_url: "https://vendor.example.com",
        claim_text: "Fast setup.",
        source_url: "https://vendor.example.com/pricing",
        impact_score: 8,
        passed_verbatim_check: true
      )

      path = File.join(Dir.mktmpdir, "claims.csv")
      count = Export::ClaimsCsvExporter.new.export(path: path)

      assert_equal 1, count
      csv = CSV.read(path, headers: true)
      assert_equal ["product_url", "claim_text", "source_url"], csv.headers
      assert_equal "Fast setup.", csv.first["claim_text"]
    end
  end

  def test_default_path_uses_human_friendly_timestamp
    exporter = Export::ClaimsCsvExporter.new
    path = exporter.default_path

    assert_match(/\Aclaims-\d{2}-[A-Z][a-z]{2}-\d{4}-\d{2}-\d{2}-\d{2}\.csv\z/, path)
  end
end
