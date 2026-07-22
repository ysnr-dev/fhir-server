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
