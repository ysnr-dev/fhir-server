Rails.application.routes.draw do
  get "/metadata", to: "capability_statements#show"
  get "/.well-known/smart-configuration", to: "smart_configurations#show"
  post "/oauth/token", to: "oauth_tokens#create"
  get "/_history", to: "histories#index"
  # Server-generated audit trail: read-only by design (no write routes).
  get "/AuditEvent", to: "audit_events#index"
  get "/AuditEvent/:id", to: "audit_events#show"
  post "/", to: "bundles#create"

  # One identical route set per supported FHIR resource type, all dispatched to
  # FhirResourcesController with the type injected via defaults. Kept as literal
  # strings (rather than Fhir::ResourceRegistry.types) so loading routes never
  # autoloads application code at boot. Keep in sync with Fhir::ResourceRegistry.
  %w[Patient MedicationRequest Medication MedicationDispense MedicationAdministration
     MedicationStatement Observation Specimen ImagingStudy DiagnosticReport
     ServiceRequest Practitioner Organization
     PractitionerRole Encounter Location
     Condition AllergyIntolerance Procedure Immunization Coverage
     DocumentReference Binary].each do |type|
    scope defaults: { resource_type: type } do
      get    "/#{type}",                   to: "fhir_resources#index"
      post   "/#{type}",                   to: "fhir_resources#create"
      put    "/#{type}",                   to: "fhir_resources#conditional_update"
      delete "/#{type}",                   to: "fhir_resources#conditional_destroy"
      post   "/#{type}/$validate",         to: "fhir_resources#validate"
      get    "/#{type}/:id/$everything",   to: "fhir_resources#everything" if type == "Patient"
      # The literal `_history` routes must precede `/#{type}/:id` so the
      # segment "_history" is never captured as an :id.
      get    "/#{type}/_history",          to: "fhir_resources#type_history"
      get    "/#{type}/:id/_history/:vid", to: "fhir_resources#vread"
      get    "/#{type}/:id/_history",      to: "fhir_resources#history"
      get    "/#{type}/:id",               to: "fhir_resources#show"
      put    "/#{type}/:id",               to: "fhir_resources#update"
      patch  "/#{type}/:id",               to: "fhir_resources#patch_update"
      delete "/#{type}/:id",               to: "fhir_resources#destroy"
    end
  end
end
