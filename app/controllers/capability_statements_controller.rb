class CapabilityStatementsController < ApplicationController
  def show
    render_fhir_resource(Fhir::CapabilityStatement.build(date: Time.current.utc.iso8601), status: :ok)
  end
end
