# frozen_string_literal: true

ENV["DATABASE_URL"] ||= "postgres://postgres:postgres@127.0.0.1:54329/ecapi_test"

require "digest"
require "json"
require "minitest/autorun"
require "rack/test"
require "sequel"
require_relative "../lib/ecapi"

class ApiTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Ecapi::App.app
  end

  def database
    @database ||= Sequel.connect(ENV.fetch("DATABASE_URL"))
  end

  def setup
    database[:event_receipts].delete
    database[:events].delete
    database[:credential_data_sets].delete
    database[:advertiser_credentials].delete

    credential_id = database[:advertiser_credentials].insert(
      advertiser_id: "adv_7c21",
      credential_digest: Digest::SHA256.hexdigest("test-token")
    )
    database[:credential_data_sets].insert(credential_id: credential_id, data_set_id: "adv_7c21")
  end

  def post_event(payload, token: "test-token")
    post "/v1/events", JSON.generate(payload), {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{token}"
    }
  end

  def purchase(overrides = {})
    {
      "data_set_id" => "adv_7c21",
      "id" => "order_118342",
      "timestamp" => 1_789_203_411,
      "event_type" => "purchase",
      "value" => 1498.00,
      "currency_code" => "NOK",
      "source" => "website",
      "user_data" => { "click_id" => "agk_test" }
    }.merge(overrides)
  end
end
