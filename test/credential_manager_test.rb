# frozen_string_literal: true

require_relative "test_helper"

class CredentialManagerTest < ApiTest
  def test_creates_a_token_that_is_stored_only_as_a_digest
    result = Ecapi::CredentialManager.new.create("adv_new", %w[set_one set_two])
    credential = database[Sequel.qualify(:ecapi, :advertiser_credentials)].where(id: result.fetch(:id)).first

    assert_equal %w[set_one set_two], result.fetch(:data_set_ids)
    refute_equal result.fetch(:token), credential.fetch(:credential_digest)
    assert_equal Digest::SHA256.hexdigest(result.fetch(:token)), credential.fetch(:credential_digest)
    assert Ecapi::Repository.new.authenticate(result.fetch(:token))
  end

  def test_rotation_revokes_the_old_token_and_preserves_dataset_access
    created = Ecapi::CredentialManager.new.create("adv_new", %w[set_one set_two])
    rotated = Ecapi::CredentialManager.new.rotate(created.fetch(:id))
    repository = Ecapi::Repository.new

    assert_nil repository.authenticate(created.fetch(:token))
    assert repository.authenticate(rotated.fetch(:token))
    assert_equal %w[set_one set_two], rotated.fetch(:data_set_ids)
  end

  def test_revocation_disables_a_credential
    created = Ecapi::CredentialManager.new.create("adv_new", ["set_one"])
    Ecapi::CredentialManager.new.revoke(created.fetch(:id))

    assert_nil Ecapi::Repository.new.authenticate(created.fetch(:token))
  end
end
