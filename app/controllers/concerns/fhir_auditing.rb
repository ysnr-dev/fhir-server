# Records one AuditEvent row per FHIR request. Implemented as an around_action
# with an ensure block (declared BEFORE the auth before_action in each
# controller) so that requests halted by authentication/authorization -- 401
# and 403 -- are audited too, which a plain after_action would miss.
module FhirAuditing
  extend ActiveSupport::Concern

  included do
    around_action :audit_fhir_request
  end

  private

  def audit_fhir_request
    yield
  ensure
    record_audit_event
  end

  # Audit failures must never break the request itself; they are logged instead.
  def record_audit_event
    interaction = audit_interaction
    AuditEvent.create!(
      id: SecureRandom.uuid,
      occurred_at: Time.current,
      client_id: @current_access_token&.oauth_client_id,
      client_name: @current_access_token&.oauth_client&.name,
      action: AuditEvent.action_for(interaction),
      interaction: interaction,
      resource_type: audit_resource_type,
      resource_id: audit_resource_id,
      request_method: request.method,
      request_path: request.fullpath,
      response_status: response.status
    )
  rescue StandardError => e
    Rails.logger.error("Audit recording failed: #{e.class}: #{e.message}")
  end

  # Controllers override these to describe what was accessed.
  def audit_interaction
    nil
  end

  def audit_resource_type
    nil
  end

  def audit_resource_id
    nil
  end
end
