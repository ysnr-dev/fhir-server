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

    old_refresh = issue_refresh_token.tap { |token| token.update!(expires_at: 40.days.ago) }
    live_refresh = issue_refresh_token

    ClientAssertionJti.create!(oauth_client_id: client.id, jti: "expired-jti",
                               expires_at: 1.minute.ago, created_at: 10.minutes.ago)
    ClientAssertionJti.create!(oauth_client_id: client.id, jti: "live-jti",
                               expires_at: 5.minutes.from_now, created_at: Time.current)

    expect { task.invoke }.to output(
      /purged 1 access token.*\npurged 1 refresh token.*\npurged 1 expired client assertion jti/
    ).to_stdout

    expect(AccessToken.exists?(old_token.id)).to be(false)
    expect(AccessToken.exists?(recent_expired.id)).to be(true)
    expect(AccessToken.exists?(live_token.id)).to be(true)
    expect(RefreshToken.exists?(old_refresh.id)).to be(false)
    expect(RefreshToken.exists?(live_refresh.id)).to be(true)
    expect(ClientAssertionJti.pluck(:jti)).to eq(["live-jti"])
  end

  def issue_refresh_token
    @launch_client ||= OauthClient.register(
      name: "purge-launch-client", scopes: "patient/*.read offline_access",
      redirect_uris: "https://app.example/cb", client_type: "public"
    ).first
    @launch_user ||= begin
      patient = Patient.create!(id: SecureRandom.uuid, content: { "resourceType" => "Patient" },
                                version_id: 1, last_updated: Time.current)
      User.create!(email: "purge@example.com", patient_id: patient.id, password: "correct-horse-battery")
    end
    code, = AuthorizationCode.issue(
      client: @launch_client, user: @launch_user, scopes: %w[patient/*.read offline_access],
      redirect_uri: "https://app.example/cb", code_challenge: "c" * 43
    )
    RefreshToken.issue(
      client: @launch_client, user: @launch_user, patient_id: @launch_user.patient_id,
      scopes: %w[patient/*.read offline_access], authorization_code: code
    ).first
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

RSpec.describe "fhir:purge_past_slots", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("fhir:purge_past_slots")
  end

  let(:task) { Rake::Task["fhir:purge_past_slots"] }

  after { task.reenable }

  it "過ぎた空き枠だけを消し、予約済みの枠と保持期間内の枠は残す" do
    old_free = create_slot(start_time: 40.days.ago, status: "free")
    old_unavailable = create_slot(start_time: 40.days.ago, status: "busy-unavailable")
    # 予約が押さえている枠は、取消・日時変更で現物を読むので消さない。
    old_booked = create_slot(start_time: 40.days.ago, status: "busy")
    recent_free = create_slot(start_time: 1.day.ago, status: "free")
    future_free = create_slot(start_time: 3.days.from_now, status: "free")
    # 論理削除済みは誰からも読めないので、状態によらず物理削除する。
    deleted = create_slot(start_time: 40.days.ago, status: "busy")
    deleted.update!(deleted: true)

    expect { task.invoke }.to output(/purged 3 slot\(s\)/).to_stdout

    expect(Slot.exists?(old_free.id)).to be(false)
    expect(Slot.exists?(old_unavailable.id)).to be(false)
    expect(Slot.exists?(deleted.id)).to be(false)
    expect(Slot.exists?(old_booked.id)).to be(true)
    expect(Slot.exists?(recent_free.id)).to be(true)
    expect(Slot.exists?(future_free.id)).to be(true)
  end

  it "消した枠の履歴(resource_versions)も残さない" do
    slot = create_slot(start_time: 40.days.ago, status: "free")
    slot.resource_versions.create!(resource_type: "Slot", version_id: 1, content: slot.content,
                                   last_updated: slot.last_updated)

    expect { task.invoke }.to output(/purged 1 slot/).to_stdout

    expect(ResourceVersion.where(resource_type: "Slot", resource_id: slot.id)).to be_empty
  end

  it "保持期間は SLOT_RETENTION_DAYS で変えられる" do
    slot = create_slot(start_time: 10.days.ago, status: "free")

    previous = ENV["SLOT_RETENTION_DAYS"]
    ENV["SLOT_RETENTION_DAYS"] = "5"
    begin
      task.invoke
    ensure
      ENV["SLOT_RETENTION_DAYS"] = previous
    end

    expect(Slot.exists?(slot.id)).to be(false)
  end

  def create_slot(start_time:, status:)
    Slot.create!(
      id: SecureRandom.uuid,
      version_id: 1,
      last_updated: Time.current,
      status: status,
      start_time: start_time,
      content: {
        "resourceType" => "Slot", "status" => status,
        "schedule" => { "reference" => "Schedule/x" },
        "start" => start_time.iso8601, "end" => (start_time + 15.minutes).iso8601
      }
    )
  end
end
