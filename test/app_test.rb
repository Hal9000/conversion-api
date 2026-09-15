# frozen_string_literal: true

require_relative "test_helper"

class AppTest < Minitest::Test
  include RequestHelpers

  def setup
    ConversionApi.reset!
  end

  def test_root
    get "/"
    assert_equal 200, last_response.status
    assert_equal "conversion-api", json_body["service"]
  end

  def test_health
    get "/health"
    assert_equal 200, last_response.status
    assert_equal "ok", json_body["status"]
    assert_equal 0, json_body["events"]
  end

  def test_missing_api_key
    post "/v1/events", JSON.generate(valid_event), "CONTENT_TYPE" => "application/json"
    assert_equal 401, last_response.status
  end

  def test_invalid_api_key
    post_json "/v1/events", valid_event, "HTTP_AUTHORIZATION" => "Bearer nope"
    assert_equal 401, last_response.status
  end

  def test_x_api_key_header
    post "/v1/events", JSON.generate(valid_event),
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_API_KEY" => "demo"
    assert_equal 200, last_response.status
  end

  def test_create_single_event
    post_json "/v1/events", valid_event
    assert_equal 200, last_response.status
    assert_equal 1, json_body["created"]
    assert_equal 0, json_body["merged"]
    assert_equal "created", json_body["events"][0]["action"]
  end

  def test_batch_events
    post_json "/v1/events", {
      "events" => [
        valid_event,
        valid_event("id" => "evt_002", "event_type" => "add_to_cart", "value" => nil, "currency_code" => nil)
      ]
    }
    assert_equal 200, last_response.status
    assert_equal 2, json_body["created"]
  end

  def test_merges_same_data_set_and_id
    post_json "/v1/events", valid_event("user_data" => { "click_id" => "clk_1" })
    post_json "/v1/events", valid_event("value" => 59.99, "user_data" => { "ifa" => "abc" })

    assert_equal 200, last_response.status
    assert_equal 1, json_body["merged"]

    get_json "/v1/events/acct_demo/evt_001"
    assert_equal 200, last_response.status
    assert_equal 59.99, json_body["value"]
    assert_equal "clk_1", json_body["user_data"]["click_id"]
    assert_equal "abc", json_body["user_data"]["ifa"]
  end

  def test_events_without_id_are_unique
    event = valid_event
    event.delete("id")
    2.times { post_json "/v1/events", event }

    get_json "/v1/events"
    assert_equal 2, json_body["events"].length
  end

  def test_missing_data_set_id
    post_json "/v1/events", valid_event("data_set_id" => "")
    assert_equal 400, last_response.status
    assert_match(/data_set_id/, json_body["details"][0]["error"])
  end

  def test_invalid_timestamp
    post_json "/v1/events", valid_event("timestamp" => "2025-05-06")
    assert_equal 400, last_response.status
    assert_match(/timestamp/, json_body["details"][0]["error"])
  end

  def test_custom_event_requires_name
    post_json "/v1/events", valid_event("event_type" => "custom")
    assert_equal 400, last_response.status
    assert_match(/custom_event/, json_body["details"][0]["error"])
  end

  def test_value_requires_currency
    body = valid_event
    body.delete("currency_code")
    post_json "/v1/events", body
    assert_equal 400, last_response.status
    assert_match(/currency_code/, json_body["details"][0]["error"])
  end

  def test_unknown_event_type
    post_json "/v1/events", valid_event("event_type" => "not_a_real_event")
    assert_equal 400, last_response.status
  end

  def test_invalid_json
    post "/v1/events", "{not-json", json_headers
    assert_equal 400, last_response.status
  end

  def test_empty_body
    post "/v1/events", "", json_headers
    assert_equal 400, last_response.status
  end

  def test_lookup_missing_event
    get_json "/v1/events/acct_demo/missing"
    assert_equal 404, last_response.status
  end

  def test_atomic_batch_rejects_all_on_one_invalid
    post_json "/v1/events", {
      "events" => [
        valid_event,
        valid_event("id" => "evt_bad", "event_type" => "nope")
      ]
    }
    assert_equal 400, last_response.status
    get_json "/v1/events"
    assert_equal [], json_body["events"]
  end
end
