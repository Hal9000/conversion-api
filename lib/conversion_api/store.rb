# frozen_string_literal: true

require "time"

module ConversionApi
  class Store
    def initialize
      @mutex = Mutex.new
      @by_key = {}
      @order = []
    end

    def ingest(events)
      @mutex.synchronize do
        events.map { |event| upsert(event) }
      end
    end

    def all
      @mutex.synchronize { @order.map { |key| deep_dup(@by_key[key]) } }
    end

    def find(data_set_id, id)
      @mutex.synchronize do
        record = @by_key[key_for(data_set_id, id)]
        record && deep_dup(record)
      end
    end

    def size
      @mutex.synchronize { @by_key.size }
    end

    def clear!
      @mutex.synchronize do
        @by_key.clear
        @order.clear
      end
    end

    private

    def upsert(event)
      id = event["id"]
      data_set_id = event["data_set_id"]

      unless id
        stored = deep_dup(event)
        stored["_action"] = "created"
        generated = SecureRandom.uuid
        stored["_store_key"] = generated
        @by_key[generated] = stored
        @order << generated
        return stored_view(stored)
      end

      key = key_for(data_set_id, id)
      if @by_key.key?(key)
        merged = merge_records(@by_key[key], event)
        merged["_action"] = "merged"
        merged["_updated_at"] = Time.now.utc.iso8601
        @by_key[key] = merged
        stored_view(merged)
      else
        stored = deep_dup(event)
        stored["_action"] = "created"
        @by_key[key] = stored
        @order << key
        stored_view(stored)
      end
    end

    def merge_records(existing, incoming)
      merged = deep_dup(existing)
      incoming.each do |k, v|
        next if k.start_with?("_")

        merged[k] = if object?(merged[k]) && object?(v)
          merged[k].merge(v)
        else
          deep_dup(v)
        end
      end
      merged
    end

    def object?(value)
      value.is_a?(Hash)
    end

    def key_for(data_set_id, id)
      "#{data_set_id}\0#{id}"
    end

    def stored_view(record)
      {
        "data_set_id" => record["data_set_id"],
        "id" => record["id"],
        "event_type" => record["event_type"],
        "action" => record["_action"]
      }
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
