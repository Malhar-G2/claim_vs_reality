require "config/environment"
require "database/connection_provider"

module Database
  class Migrator
    MIGRATIONS_DIR = File.expand_path("../../db/migrations", __dir__)
    SCHEMA_MIGRATION_PATH = File.join(MIGRATIONS_DIR, "001_create_schema_migrations.sql")

    def initialize(connection: ConnectionProvider.new.call)
      @connection = connection
    end

    def migrate!
      ensure_schema_migrations!

      migration_files.each do |path|
        version = File.basename(path).split("_").first
        next if migrated?(version)

        begin
          @connection.transaction
          @connection.execute_batch(File.read(path))
          @connection.execute(
            "INSERT INTO schema_migrations(version, applied_at) VALUES(?, ?)",
            [version, Time.now.utc.iso8601]
          )
          @connection.commit
        rescue StandardError
          @connection.rollback
          raise
        end
      end
    end

    private

    def ensure_schema_migrations!
      @connection.execute_batch(File.read(SCHEMA_MIGRATION_PATH))
    end

    def migration_files
      Dir[File.join(MIGRATIONS_DIR, "*.sql")].sort
    end

    def migrated?(version)
      row = @connection.get_first_row(
        "SELECT version FROM schema_migrations WHERE version = ?",
        [version]
      )
      !row.nil?
    end
  end
end
