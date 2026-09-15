# frozen_string_literal: true

require "digest"
require "json"
require "rack/utils"
require "roda"
require "sequel"
require "sequel/extensions/pg_json"
require "securerandom"
require "time"

module Ecapi
  class DatabaseConfigurationError < StandardError; end

  class DatabaseUrl
    def self.fetch
      database_url = ENV.fetch("DATABASE_URL")
      return database_url unless ENV["RACK_ENV"] == "production"
      return database_url if database_url.match?(/(?:\?|&)sslmode=verify-full(?:&|\z)/)

      raise DatabaseConfigurationError, "production DATABASE_URL must set sslmode=verify-full"
    end
  end

  class ValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super("event validation failed")
    end
  end

  class Validator
    REQUIRED_FIELDS = %w[data_set_id id timestamp event_type source].freeze

    def self.validate!(event)
      unless event.is_a?(Hash)
        raise ValidationError, ["event must be a JSON object"]
      end

      errors = REQUIRED_FIELDS.filter_map do |field|
        "#{field} is required" if event[field].nil? || event[field].to_s.empty?
      end
      errors << "timestamp must be a Unix timestamp integer" unless event["timestamp"].is_a?(Integer)
      errors << "purchase requires a non-negative numeric value" if event["event_type"] == "purchase" &&
        (!event["value"].is_a?(Numeric) || event["value"].negative?)
      errors << "purchase requires a three-letter currency_code" if event["event_type"] == "purchase" &&
        event["currency_code"] !~ /\A[A-Z]{3}\z/
      errors << "custom requires custom_event" if event["event_type"] == "custom" &&
        event["custom_event"].to_s.empty?
      raise ValidationError, errors unless errors.empty?

      event
    end
  end

  class Repository
    def initialize(database_url = DatabaseUrl.fetch)
      @db = Sequel.connect(database_url)
    end

    def healthy?
      @db.get(Sequel.lit("1")) == 1
    rescue Sequel::Error
      false
    end

    def authenticate(token)
      return nil if token.nil? || token.empty?

      table(:advertiser_credentials)
        .where(credential_digest: Digest::SHA256.hexdigest(token), active: true)
        .first
    end

    def authorized?(credential, data_set_id)
      !table(:credential_data_sets)
        .where(credential_id: credential[:id], data_set_id: data_set_id)
        .empty?
    end

    def receive(credential, events)
      request_id = SecureRandom.uuid

      @db.transaction do
        results = events.map do |event|
          ingest_event(credential, event, request_id)
        end
        { request_id: request_id, events: results }
      end
    end

    private

    def table(name)
      @db[Sequel.qualify(:ecapi, name)]
    end

    def ingest_event(credential, event, request_id)
      lock_key = Digest::SHA256.hexdigest("#{event.fetch("data_set_id")}\0#{event.fetch("id")}")
      @db.fetch("SELECT pg_advisory_xact_lock(hashtext(?))", lock_key).all

      event_table = table(:events)
      existing = event_table.where(
        data_set_id: event.fetch("data_set_id"),
        external_event_id: event.fetch("id")
      ).first

      if existing
        outcome = "duplicate"
        event_id = existing[:id]
      else
        outcome = "created"
        event_id = event_table.insert(
          data_set_id: event.fetch("data_set_id"),
          external_event_id: event.fetch("id"),
          event_type: event.fetch("event_type"),
          source: event.fetch("source"),
          occurred_at: Time.at(event.fetch("timestamp")).utc,
          payload: Sequel.pg_jsonb(event)
        )
      end

      table(:event_receipts).insert(
        request_id: request_id,
        credential_id: credential.fetch(:id),
        event_id: event_id,
        outcome: outcome,
        raw_payload: Sequel.pg_jsonb(event)
      )

      {
        data_set_id: event.fetch("data_set_id"),
        id: event.fetch("id"),
        outcome: outcome
      }
    end
  end

  class UnknownCredentialError < StandardError; end

  class CredentialManager
    def initialize(database_url = DatabaseUrl.fetch)
      @db = Sequel.connect(database_url)
    end

    def create(advertiser_id, data_set_ids)
      raise ArgumentError, "advertiser_id is required" if advertiser_id.to_s.empty?
      raise ArgumentError, "at least one data_set_id is required" if data_set_ids.empty?

      @db.transaction do
        credential_id, token = create_credential(advertiser_id, data_set_ids)
        { id: credential_id, token: token, data_set_ids: data_set_ids.uniq }
      end
    end

    def rotate(credential_id)
      @db.transaction do
        credentials = table(:advertiser_credentials)
        credential = credentials.where(id: credential_id).for_update.first
        raise UnknownCredentialError, "credential #{credential_id} does not exist" unless credential

        data_set_ids = table(:credential_data_sets)
          .where(credential_id: credential_id)
          .select_map(:data_set_id)
        new_id, token = create_credential(credential.fetch(:advertiser_id), data_set_ids)
        credentials.where(id: credential_id).update(active: false)

        { id: new_id, token: token, data_set_ids: data_set_ids }
      end
    end

    def revoke(credential_id)
      updated = table(:advertiser_credentials).where(id: credential_id, active: true).update(active: false)
      raise UnknownCredentialError, "active credential #{credential_id} does not exist" if updated.zero?
    end

    private

    def create_credential(advertiser_id, data_set_ids)
      token = SecureRandom.urlsafe_base64(32)
      credential_id = table(:advertiser_credentials).insert(
        advertiser_id: advertiser_id,
        credential_digest: Digest::SHA256.hexdigest(token)
      )
      table(:credential_data_sets).multi_insert(
        data_set_ids.uniq.map { |data_set_id| { credential_id: credential_id, data_set_id: data_set_id } }
      )
      [credential_id, token]
    end

    def table(name)
      @db[Sequel.qualify(:ecapi, name)]
    end
  end

  class Service
    def initialize(repository = Repository.new)
      @repository = repository
    end

    def receive(token, payload)
      credential = @repository.authenticate(token)
      return [:unauthorized, { error: "Unauthorized" }] unless credential

      events = extract_events(payload)
      events.each { |event| Validator.validate!(event) }
      unless events.all? { |event| @repository.authorized?(credential, event.fetch("data_set_id")) }
        return [:forbidden, { error: "Forbidden", details: "credential is not authorized for data_set_id" }]
      end

      [:ok, @repository.receive(credential, events)]
    rescue ValidationError => error
      [:bad_request, { error: "Bad Request", details: error.errors }]
    end

    private

    def extract_events(payload)
      return payload if payload.is_a?(Array)
      return payload.fetch("events") if payload.is_a?(Hash) && payload.key?("events")
      return [payload] if payload.is_a?(Hash)

      raise ValidationError, ["request body must contain an event or events array"]
    end
  end

  class App < Roda
    plugin :json
    plugin :halt
    plugin :all_verbs

    route do |r|
      r.get "health" do
        repository = Repository.new
        App.halt_json(r, 503, "Service Unavailable") unless repository.healthy?

        { status: "ok", database: "ok" }
      rescue DatabaseConfigurationError, Sequel::Error
        App.halt_json(r, 503, "Service Unavailable")
      end

      r.on "v1" do
        r.post "events" do
          body = r.body.read
          App.halt_json(r, 400, "Bad Request", ["request body is required"]) if body.strip.empty?

          payload = JSON.parse(body)
          status, response = Service.new.receive(App.bearer_token(r), payload)
          case status
          when :ok then response
          when :bad_request then App.halt_json(r, 400, response.fetch(:error), response.fetch(:details))
          when :unauthorized then App.halt_json(r, 401, response.fetch(:error))
          when :forbidden then App.halt_json(r, 403, response.fetch(:error), response.fetch(:details))
          end
        rescue JSON::ParserError
          App.halt_json(r, 400, "Bad Request", ["request body must be valid JSON"])
        end
      end
    end

    def self.halt_json(request, status, error, details = nil)
      response = { error: error }
      response[:details] = details if details
      request.halt status, response
    end

    def self.bearer_token(request)
      value = request.env.fetch("HTTP_AUTHORIZATION", "")
      return nil unless value.start_with?("Bearer ")

      value.delete_prefix("Bearer ").strip
    end
  end
end
