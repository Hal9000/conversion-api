# frozen_string_literal: true

require_relative "test_helper"

class EventReceiverTest < ApiTest
  def test_persists_an_authenticated_purchase
    post_event(purchase)

    assert_equal 200, last_response.status
    response = JSON.parse(last_response.body)
    assert_match(/\A[0-9a-f-]{36}\z/, response.fetch("request_id"))
    assert_equal "created", response.fetch("events").first.fetch("outcome")
    assert_equal 1, database[:events].count
    assert_equal 1, database[:event_receipts].count
  end

  def test_rejects_an_invalid_bearer_token_without_persisting
    post_event(purchase, token: "wrong-token")

    assert_equal 401, last_response.status
    assert_equal 0, database[:events].count
    assert_equal 0, database[:event_receipts].count
  end

  def test_rejects_a_dataset_not_authorized_for_the_credential
    post_event(purchase("data_set_id" => "adv_other"))

    assert_equal 403, last_response.status
    assert_equal 0, database[:events].count
  end

  def test_rejects_malformed_json_without_persisting
    post "/v1/events", "{", {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer test-token"
    }

    assert_equal 400, last_response.status
    assert_equal 0, database[:events].count
  end

  def test_rejects_a_purchase_without_currency
    post_event(purchase("currency_code" => nil))

    assert_equal 400, last_response.status
    assert_equal 0, database[:events].count
  end

  def test_records_a_retry_without_creating_a_second_event
    post_event(purchase)
    post_event(purchase)

    assert_equal 200, last_response.status
    assert_equal "duplicate", JSON.parse(last_response.body).fetch("events").first.fetch("outcome")
    assert_equal 1, database[:events].count
    assert_equal 2, database[:event_receipts].count
  end
end
