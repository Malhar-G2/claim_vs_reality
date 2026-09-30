require "bundler/setup"
require "dotenv/load"
require "sqlite3"
require "json"
require "csv"
require "net/http"
require "uri"
require "time"
require "fileutils"
require "tmpdir"
require "securerandom"
require "digest"
require "logger"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("..", __dir__))
