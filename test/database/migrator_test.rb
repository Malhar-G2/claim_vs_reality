require "test_helper"
require "database/migrator"

class Database::MigratorTest < Minitest::Test
  def test_migrate_creates_core_tables
    with_temp_db do |db_path|
      Database::Migrator.new.migrate!

      db = SQLite3::Database.new(db_path)
      tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

      %w[
        schema_migrations
        products
        crawl_runs
        source_pages
        batch_jobs
        batch_requests
        raw_model_responses
        parsed_claims
      ].each do |table_name|
        assert_includes tables, table_name
      end
    end
  end
end
