# frozen_string_literal: true

require "json"
require "time"
require "securerandom"

require_relative "conversion_api/version"
require_relative "conversion_api/catalog"
require_relative "conversion_api/validator"
require_relative "conversion_api/store"
require_relative "conversion_api/app"

module ConversionApi
  def self.store
    @store ||= Store.new
  end

  def self.reset!
    @store = Store.new
  end

  def self.api_key
    ENV.fetch("CONVERSION_API_KEY", "demo")
  end

  def self.app
    App.app
  end
end
