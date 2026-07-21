class CapabilityStatementsController < ApplicationController
  def show
    render_fhir_resource(Fhir::CapabilityStatement.build(date: Time.current.utc.iso8601, base_url: base_url), status: :ok)
  end
end
