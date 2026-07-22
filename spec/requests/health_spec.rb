require "rails_helper"

RSpec.describe "Health check", type: :request do
  describe "GET /up" do
    it "returns 200 when the database is reachable" do
      get "/up"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("status" => "ok")
    end

    it "returns 503 without leaking details when the database is down" do
      allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(ActiveRecord::ConnectionNotEstablished)

      get "/up"

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)).to eq("status" => "error")
    end

    it "is not audited" do
      expect { get "/up" }.not_to change(AuditEvent, :count)
    end

    it "requires no bearer token even when auth is enabled" do
      with_fhir_auth do
        get "/up"
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
