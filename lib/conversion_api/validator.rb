# frozen_string_literal: true

module ConversionApi
  class Validator
    Result = Struct.new(:ok, :events, :errors, keyword_init: true)

    def initialize(payload)
      @payload = payload
    end

    def call
      events, extract_error = extract_events
      return fail_all([extract_error]) if extract_error

      errors = []
      normalized = events.each_with_index.filter_map do |event, index|
        issue = validate_event(event, index)
        if issue
          errors << issue
          next
        end
        normalize(event)
      end

      return fail_all(errors) unless errors.empty?

      Result.new(ok: true, events: normalized, errors: [])
    end

    private

    def fail_all(errors)
      Result.new(ok: false, events: [], errors: errors)
    end

    def extract_events
      case @payload
      when Array
        return [nil, error(nil, "events array must not be empty")] if @payload.empty?

        [@payload, nil]
      when Hash
        if @payload.key?("events")
          events = @payload["events"]
          unless events.is_a?(Array)
            return [nil, error(nil, "events must be an array")]
          end
          return [nil, error(nil, "events array must not be empty")] if events.empty?

          [events, nil]
        else
          [[@payload], nil]
        end
      else
        [nil, error(nil, "request body must be a JSON object or array")]
      end
    end

    def validate_event(event, index)
      unless event.is_a?(Hash)
        return error(index, "event must be an object")
      end

      data_set_id = event["data_set_id"]
      if blank?(data_set_id) || !data_set_id.is_a?(String)
        return error(index, "data_set_id is required")
      end

      timestamp = event["timestamp"]
      unless timestamp.is_a?(Integer) && timestamp.positive?
        return error(index, "timestamp is required and must be a unix epoch integer")
      end

      event_type = event["event_type"]
      if blank?(event_type) || !event_type.is_a?(String)
        return error(index, "event_type is required")
      end
      unless Catalog::EVENT_TYPES.include?(event_type)
        return error(index, "event_type is invalid")
      end

      if event_type == "custom"
        if blank?(event["custom_event"]) || !event["custom_event"].is_a?(String)
          return error(index, "custom_event is required when event_type is custom")
        end
      end

      if event.key?("value") && !event["value"].nil?
        unless event["value"].is_a?(Numeric)
          return error(index, "value must be a number")
        end
        currency = event["currency_code"]
        if blank?(currency) || !currency.is_a?(String)
          return error(index, "currency_code is required when value is set")
        end
        unless currency.match?(/\A[A-Z]{3}\z/)
          return error(index, "currency_code must be an ISO 4217 code")
        end
      end

      if event.key?("source") && !event["source"].nil?
        unless Catalog::SOURCES.include?(event["source"])
          return error(index, "source is invalid")
        end
      end

      if event.key?("user_data") && !event["user_data"].nil? && !event["user_data"].is_a?(Hash)
        return error(index, "user_data must be an object")
      end

      if event.key?("properties") && !event["properties"].nil? && !event["properties"].is_a?(Hash)
        return error(index, "properties must be an object")
      end

      nil
    end

    def normalize(event)
      copy = deep_dup(event)
      copy["id"] = copy["id"].to_s unless blank?(copy["id"])
      copy["_received_at"] = Time.now.utc.iso8601
      copy
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def error(index, message)
      { index: index, error: message }
    end

    def deep_dup(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
      when Array
        value.map { |v| deep_dup(v) }
      else
        value
      end
    end
  end
end
