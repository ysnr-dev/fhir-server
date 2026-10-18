require "rails_helper"

# Browser-hosted SMART apps (public clients) call the token endpoint and the
# FHIR API directly, so those answer CORS for any origin; the cookie-bearing
# authorize pages and the admin API never do.
RSpec.describe "CORS", type: :request do
  let(:origin) { "https://app.example" }

  def preflight(path, method)
    options path, headers: { "Origin" => origin, "Access-Control-Request-Method" => method }
  end

  it "answers preflight for the token endpoint" do
    preflight("/oauth/token", "POST")

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    expect(response.headers["Access-Control-Allow-Methods"]).to include("POST")
  end

  it "answers preflight for FHIR resources and exposes ETag/Location" do
    preflight("/Patient/abc", "PUT")

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    expect(response.headers["Access-Control-Expose-Headers"]).to include("ETag", "Location")
  end

  it "adds the allow-origin header to actual FHIR and discovery responses" do
    get "/.well-known/smart-configuration", headers: { "Origin" => origin }
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")

    get "/metadata", headers: { "Origin" => origin }
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")

    get "/Patient", headers: { "Origin" => origin }
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
  end

  it "does not open the authorize pages, the admin API or introspection" do
    preflight("/oauth/authorize", "GET")
    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil

    preflight("/admin/launch_contexts", "POST")
    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil

    preflight("/oauth/introspect", "POST")
    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end
end
