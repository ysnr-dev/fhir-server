class BundlesController < ApplicationController
  include FhirAuditing # first, so halted (401/403) requests are audited too

  def create
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error
    return render_bad_request("resourceType must be 'Bundle'") unless payload["resourceType"] == "Bundle"

    # Remembered for the audit trail (transaction vs batch).
    @audit_bundle_type = payload["type"] if BundleProcessor::VALID_TYPES.include?(payload["type"])
    return unless authorize_fhir_request!(entry_scope_checks(payload))

    result = BundleProcessor.call(payload, base_url: base_url)
    render json: result.body, status: result.status, content_type: FhirResponse::FHIR_CONTENT_TYPE
  end

  private

  # nil (-> no subtype) when the body was too malformed to classify.
  def audit_interaction
    @audit_bundle_type
  end

  # One scope check per entry, derived from its request method and url type.
  # Entries too malformed to derive a check from are left for BundleProcessor
  # to reject; a scope failure 403s the whole bundle before anything runs.
  def entry_scope_checks(payload)
    Array(payload["entry"]).filter_map do |entry|
      request_hash = entry.is_a?(Hash) ? entry["request"] : nil
      next unless request_hash.is_a?(Hash)

      type = request_hash["url"].to_s.split("?").first.to_s.split("/").reject(&:empty?).first
      next if type.blank?

      [type, request_hash["method"].to_s.upcase == "GET" ? :read : :write]
    end
  end
end
