# frozen_string_literal: true

require "sequel"

database_url = ENV.fetch("DATABASE_URL") do
  abort "DATABASE_URL is required (for example: postgres://postgres:postgres@localhost:54329/ecapi_test)"
end

Sequel::Migrator.run(Sequel.connect(database_url), File.expand_path("migrations", __dir__))
