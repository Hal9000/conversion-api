# frozen_string_literal: true

ENV["CONVERSION_API_KEY"] ||= "demo"

require "minitest/autorun"
require "rack/test"
require "json"
require_relative "../lib/conversion_api"

module RequestHelpers
  include Rack::Test::Methods

  def app
    ConversionApi.app
  end

  def json_headers(extra = {})
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer demo"
    }.merge(extra)
  end

  def post_json(path, body, headers = {})
    post path, JSON.generate(body), json_headers(headers)
  end

  def get_json(path, headers = {})
    get path, {}, json_headers(headers)
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def valid_event(overrides = {})
    {
      "data_set_id" => "acct_demo",
      "id" => "evt_001",
      "timestamp" => 1_746_558_464,
      "event_type" => "purchase",
      "value" => 49.99,
      "currency_code" => "USD",
      "source" => "website"
    }.merge(overrides)
  end
end
