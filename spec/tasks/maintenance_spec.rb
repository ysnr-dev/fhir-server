require "rails_helper"
require "rake"

RSpec.describe "fhir:purge_expired", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("fhir:purge_expired")
  end

  let(:task) { Rake::Task["fhir:purge_expired"] }
  let(:client) { OauthClient.register(name: "purge-client", scopes: "system/*.read").first }

  after { task.reenable }

  it "deletes tokens expired beyond the retention window and expired jtis, keeping the rest" do
    old_token, = AccessToken.issue(client, scopes: ["system/*.read"])
    old_token.update!(expires_at: 40.days.ago)
    recent_expired, = AccessToken.issue(client, scopes: ["system/*.read"])
    recent_expired.update!(expires_at: 1.day.ago)
    live_token, = AccessToken.issue(client, scopes: ["system/*.read"])

    ClientAssertionJti.create!(oauth_client_id: client.id, jti: "expired-jti",
                               expires_at: 1.minute.ago, created_at: 10.minutes.ago)
    ClientAssertionJti.create!(oauth_client_id: client.id, jti: "live-jti",
                               expires_at: 5.minutes.from_now, created_at: Time.current)

    expect { task.invoke }.to output(/purged 1 access token.*\npurged 1 expired client assertion jti/).to_stdout

    expect(AccessToken.exists?(old_token.id)).to be(false)
    expect(AccessToken.exists?(recent_expired.id)).to be(true)
    expect(AccessToken.exists?(live_token.id)).to be(true)
    expect(ClientAssertionJti.pluck(:jti)).to eq(["live-jti"])
  end
end

RSpec.describe "fhir:purge_bulk_exports", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("fhir:purge_bulk_exports")
  end

  let(:task) { Rake::Task["fhir:purge_bulk_exports"] }

  after { task.reenable }

  def create_export(status:, updated_at: Time.current, created_at: Time.current)
    export = BulkExport.create!(
      id: SecureRandom.uuid, kind: "system", status: status,
      output_format: "application/fhir+ndjson", transaction_time: Time.current,
      request_url: "http://example.test/$export"
    )
    export.update_columns(updated_at: updated_at, created_at: created_at)
    export
  end

  it "fails a stale in-progress export but leaves a fresh one running" do
    stale = create_export(status: "in_progress", updated_at: 2.hours.ago)
    fresh = create_export(status: "in_progress", updated_at: 1.minute.ago)

    expect { task.invoke }.to output(/marked 1 stale in-progress export/).to_stdout

    expect(stale.reload.status).to eq("failed")
    expect(fresh.reload.status).to eq("in_progress")
  end

  it "purges finished exports past retention but keeps recent ones" do
    old_completed = create_export(status: "completed", created_at: 10.days.ago)
    recent_completed = create_export(status: "completed", created_at: 1.hour.ago)

    expect { task.invoke }.to output(/purged 1 export/).to_stdout

    expect(BulkExport.exists?(old_completed.id)).to be(false)
    expect(BulkExport.exists?(recent_completed.id)).to be(true)
  end
end
