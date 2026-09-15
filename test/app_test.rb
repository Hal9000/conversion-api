# frozen_string_literal: true

require_relative "test_helper"

class EventReceiverTest < ApiTest
  def test_production_database_url_requires_certificate_verification
    previous_environment = ENV["RACK_ENV"]
    previous_url = ENV["DATABASE_URL"]
    ENV["RACK_ENV"] = "production"
    ENV["DATABASE_URL"] = "postgres://postgres:postgres@127.0.0.1:5432/ecapi_test?sslmode=require"

    assert_raises(Ecapi::DatabaseConfigurationError) { Ecapi::DatabaseUrl.fetch }
  ensure
    ENV["RACK_ENV"] = previous_environment
    ENV["DATABASE_URL"] = previous_url
  end

  def test_health_requires_a_database_connection
    get "/health"

    assert_equal 200, last_response.status
    assert_equal({ "status" => "ok", "database" => "ok" }, JSON.parse(last_response.body))
  end

  def test_persists_an_authenticated_purchase
    post_event(purchase)

    assert_equal 200, last_response.status
    response = JSON.parse(last_response.body)
    assert_match(/\A[0-9a-f-]{36}\z/, response.fetch("request_id"))
    assert_equal "created", response.fetch("events").first.fetch("outcome")
    assert_equal 1, database[Sequel.qualify(:ecapi, :events)].count
    assert_equal 1, database[Sequel.qualify(:ecapi, :event_receipts)].count
  end

  def test_rejects_an_invalid_bearer_token_without_persisting
    post_event(purchase, token: "wrong-token")

    assert_equal 401, last_response.status
    assert_equal 0, database[Sequel.qualify(:ecapi, :events)].count
    assert_equal 0, database[Sequel.qualify(:ecapi, :event_receipts)].count
  end

  def test_rejects_a_dataset_not_authorized_for_the_credential
    post_event(purchase("data_set_id" => "adv_other"))

    assert_equal 403, last_response.status
    assert_equal 0, database[Sequel.qualify(:ecapi, :events)].count
  end

  def test_rejects_malformed_json_without_persisting
    post "/v1/events", "{", {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer test-token"
    }

    assert_equal 400, last_response.status
    assert_equal 0, database[Sequel.qualify(:ecapi, :events)].count
  end

  def test_rejects_a_purchase_without_currency
    post_event(purchase("currency_code" => nil))

    assert_equal 400, last_response.status
    assert_equal 0, database[Sequel.qualify(:ecapi, :events)].count
  end

  def test_rejects_an_invalid_batch_without_persisting_any_events
    post_event([
      purchase("id" => "order_valid"),
      purchase("id" => "order_invalid", "currency_code" => nil)
    ])

    assert_equal 400, last_response.status
    details = JSON.parse(last_response.body).fetch("details")
    assert_equal({ "index" => 1, "error" => "purchase requires a three-letter currency_code" }, details.first)
    assert_equal 0, database[Sequel.qualify(:ecapi, :events)].count
    assert_equal 0, database[Sequel.qualify(:ecapi, :event_receipts)].count
  end

  def test_rejects_a_request_larger_than_one_megabyte
    post_event(purchase("properties" => { "padding" => "x" * Ecapi::App::MAX_REQUEST_BYTES }))

    assert_equal 413, last_response.status
    assert_equal 0, database[Sequel.qualify(:ecapi, :events)].count
  end

  def test_records_a_retry_without_creating_a_second_event
    post_event(purchase)
    post_event(purchase)

    assert_equal 200, last_response.status
    assert_equal "duplicate", JSON.parse(last_response.body).fetch("events").first.fetch("outcome")
    assert_equal 1, database[Sequel.qualify(:ecapi, :events)].count
    assert_equal 2, database[Sequel.qualify(:ecapi, :event_receipts)].count
  end
end
