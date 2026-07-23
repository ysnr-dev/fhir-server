Rails.application.routes.draw do
  # LB用ヘルスチェック(認証・監査・SSL/Host検査の対象外)
  get "/up", to: "health#show"

  get "/metadata", to: "capability_statements#show"
  get "/.well-known/smart-configuration", to: "smart_configurations#show"
  post "/oauth/token", to: "oauth_tokens#create"
  post "/oauth/revoke", to: "oauth_revocations#create"
  get "/_history", to: "histories#index"
  # Server-generated audit trail: read-only by design (no write routes).
  get "/AuditEvent", to: "audit_events#index"
  get "/AuditEvent/:id", to: "audit_events#show"
  post "/", to: "bundles#create"

  # Bulk Data $export (Bulk Data Access IG v2.0.0). Must be declared before the
  # resource-type loop below so "/Patient/$export" is matched here rather than
  # falling through to "GET /Patient/:id" with :id == "$export".
  match "/$export",         to: "bulk_exports#kickoff", via: %i[get post], defaults: { kind: "system" }
  match "/Patient/$export", to: "bulk_exports#kickoff", via: %i[get post], defaults: { kind: "patient" }
  get    "/$export/status/:id", to: "bulk_exports#status"
  delete "/$export/status/:id", to: "bulk_exports#cancel"
  get    "/$export/files/:id",  to: "bulk_exports#download"

  # One identical route set per supported FHIR resource type, all dispatched to
  # FhirResourcesController with the type injected via defaults. Kept as literal
  # strings (rather than Fhir::ResourceRegistry.types) so loading routes never
  # autoloads application code at boot. Keep in sync with Fhir::ResourceRegistry.
  %w[Patient MedicationRequest Medication MedicationDispense MedicationAdministration
     MedicationStatement Observation Specimen ImagingStudy DiagnosticReport
     ServiceRequest Practitioner Organization
     PractitionerRole Encounter Location
     Condition AllergyIntolerance Procedure Immunization Coverage
     Composition DocumentReference Binary].each do |type|
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
