# One audited FHIR request. Not part of Fhir::ResourceRegistry on purpose:
# audit rows are server-generated and immutable via the API (read/search only,
# no create/update/delete/versioning), so they don't share the generic
# resource plumbing.
class AuditEvent < ApplicationRecord
  # AuditEvent.action derived from the RESTful interaction.
  ACTION_BY_INTERACTION = {
    "create" => "C",
    "read" => "R", "vread" => "R",
    "history-instance" => "R", "history-type" => "R", "history-system" => "R",
    "update" => "U", "patch" => "U",
    "delete" => "D",
    "search-type" => "E", "transaction" => "E", "batch" => "E", "operation" => "E"
  }.freeze

  def self.action_for(interaction)
    ACTION_BY_INTERACTION.fetch(interaction, "E")
  end

  # AuditEvent.outcome: 0 = success, 4 = minor failure, 8 = serious failure.
  def outcome_code
    return "0" if response_status < 400
    return "4" if response_status < 500

    "8"
  end

  def to_fhir
    resource = {
      "resourceType" => "AuditEvent",
      "id" => id,
      "type" => {
        "system" => "http://terminology.hl7.org/CodeSystem/audit-event-type",
        "code" => "rest",
        "display" => "RESTful Operation"
      },
      "action" => action,
      "recorded" => occurred_at.utc.iso8601(3),
      "outcome" => outcome_code,
      "agent" => [agent_component],
      "source" => { "observer" => { "display" => "fhir-server" } },
      "entity" => [entity_component]
    }
    resource["subtype"] = [{ "system" => "http://hl7.org/fhir/restful-interaction", "code" => interaction }] if interaction
    resource
  end

  private

  def agent_component
    agent = { "requestor" => true, "who" => { "display" => client_name || "anonymous" } }
    agent["who"]["identifier"] = { "value" => client_id } if client_id
    agent
  end

  def entity_component
    entity = { "description" => "#{request_method} #{request_path}" }
    if resource_type.present? && resource_id.present?
      entity["what"] = { "reference" => "#{resource_type}/#{resource_id}" }
    elsif resource_type.present?
      entity["what"] = { "display" => resource_type }
    end
    entity
  end
end
