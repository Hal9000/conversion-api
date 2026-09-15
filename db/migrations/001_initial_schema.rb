# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:advertiser_credentials) do
      primary_key :id
      String :advertiser_id, null: false
      String :credential_digest, null: false, unique: true
      TrueClass :active, null: false, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:credential_data_sets) do
      foreign_key :credential_id, :advertiser_credentials, null: false, on_delete: :cascade
      String :data_set_id, null: false
      primary_key %i[credential_id data_set_id]
    end

    create_table(:events) do
      primary_key :id
      String :data_set_id, null: false
      String :external_event_id, null: false
      String :event_type, null: false
      String :source, null: false
      DateTime :occurred_at, null: false
      column :payload, :jsonb, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      unique %i[data_set_id external_event_id], name: :events_idempotency_key
    end

    create_table(:event_receipts) do
      primary_key :id
      String :request_id, null: false
      foreign_key :credential_id, :advertiser_credentials, null: false
      foreign_key :event_id, :events
      String :outcome, null: false
      column :raw_payload, :jsonb, null: false
      DateTime :received_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :request_id
      index :event_id
    end
  end
end
