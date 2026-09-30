module Database
  class ConnectionProvider
    DEFAULT_PATH = File.expand_path("../../db/claims_extractor.sqlite3", __dir__)

    def call
      path = ENV.fetch("SQLITE_DB_PATH", DEFAULT_PATH)
      FileUtils.mkdir_p(File.dirname(path))

      db = SQLite3::Database.new(path)
      db.results_as_hash = true
      db.execute("PRAGMA foreign_keys = ON")
      db.execute("PRAGMA journal_mode = WAL")
      db
    end
  end
end
