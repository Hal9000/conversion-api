begin
  require "dotenv/load"
rescue LoadError
  nil
end

require_relative "lib/conversion_api"

run ConversionApi.app
