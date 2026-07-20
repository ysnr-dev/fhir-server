module Fhir
  # Builds the server's CapabilityStatement from Fhir::ResourceRegistry so the
  # advertised resources, profiles, and search parameters stay in sync with what
  # the server actually implements instead of being hand-maintained.
  module CapabilityStatement
    SERVER_INTERACTIONS = %w[transaction batch].freeze
    RESOURCE_INTERACTIONS = %w[read vread update delete history-instance search-type create].freeze

    # Maps a search-definition param type (see Fhir::SearchDefinitions) to its
    # FHIR search parameter type code.
    SEARCH_PARAM_TYPES = {
      identifier: "token",
      string: "string",
      token: "token",
      boolean: "token",
      date: "date",
      datetime: "date",
      reference: "reference",
      token_or_text: "token"
    }.freeze

    module_function

    def build(date:)
      {
        "resourceType" => "CapabilityStatement",
        "status" => "active",
        "date" => date,
        "kind" => "instance",
        "fhirVersion" => "4.0.1",
        "format" => %w[application/fhir+json json],
        "rest" => [
          {
            "mode" => "server",
            "interaction" => SERVER_INTERACTIONS.map { |code| { "code" => code } },
            "resource" => ResourceRegistry.types.map { |type| resource_component(type) }
          }
        ]
      }
    end

    def resource_component(resource_type)
      entry = ResourceRegistry.entry_for(resource_type)
      {
        "type" => resource_type,
        "profile" => entry.fetch(:profile),
        "interaction" => RESOURCE_INTERACTIONS.map { |code| { "code" => code } },
        "searchParam" => search_params(entry.fetch(:search_params))
      }
    end

    # _id and _lastUpdated are handled implicitly by Fhir::Search for every type,
    # so they bracket the type-specific params rather than living in the definitions.
    def search_params(definitions)
      declared = definitions.map do |name, definition|
        { "name" => name, "type" => SEARCH_PARAM_TYPES.fetch(definition[:type]) }
      end

      [{ "name" => "_id", "type" => "token" }] + declared + [{ "name" => "_lastUpdated", "type" => "date" }]
    end
  end
end
