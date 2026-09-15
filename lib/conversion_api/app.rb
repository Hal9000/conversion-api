# frozen_string_literal: true

require "roda"
require "json"

module ConversionApi
  class App < Roda
    plugin :json
    plugin :halt
    plugin :all_verbs
    plugin :request_headers

    route do |r|
      r.root do
        {
          service: "conversion-api",
          version: VERSION,
          spec: "IAB Tech Lab ECAPI 1.0"
        }
      end

      r.get "health" do
        {
          status: "ok",
          service: "conversion-api",
          version: VERSION,
          events: ConversionApi.store.size,
          time: Time.now.utc.iso8601
        }
      end

      r.on "v1" do
        r.post "events" do
          authenticate!
          payload = parse_json!
          result = Validator.new(payload).call
          unless result.ok
            r.halt 400, {
              error: "Bad Request",
              details: result.errors
            }
          end

          summaries = ConversionApi.store.ingest(result.events)
          created = summaries.count { |s| s["action"] == "created" }
          merged = summaries.count { |s| s["action"] == "merged" }

          {
            status: "ok",
            received: summaries.length,
            created: created,
            merged: merged,
            events: summaries
          }
        end

        r.get "events" do
          authenticate!
          { events: ConversionApi.store.all.map { |e| public_event(e) } }
        end

        r.on "events" do
          r.is String, String do |data_set_id, id|
            r.get do
              authenticate!
              event = ConversionApi.store.find(data_set_id, id)
              r.halt 404, { error: "Not Found" } unless event
              public_event(event)
            end
          end
        end
      end
    end

    private

    def authenticate!
      expected = ConversionApi.api_key
      provided = bearer_token || request.env["HTTP_X_API_KEY"]
      return if provided == expected

      request.halt 401, { error: "Unauthorized" }
    end

    def bearer_token
      header = request.env["HTTP_AUTHORIZATION"].to_s
      return header.delete_prefix("Bearer ").strip if header.start_with?("Bearer ")
      return header.strip unless header.empty?

      nil
    end

    def parse_json!
      body = request.body.read
      request.body.rewind
      if body.nil? || body.strip.empty?
        request.halt 400, { error: "Bad Request", details: [{ index: nil, error: "request body is required" }] }
      end

      JSON.parse(body)
    rescue JSON::ParserError
      request.halt 400, { error: "Bad Request", details: [{ index: nil, error: "request body must be valid JSON" }] }
    end

    def public_event(event)
      event.reject { |k, _| k.start_with?("_") }
    end
  end
end
