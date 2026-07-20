Rails.application.routes.draw do
  get "/metadata", to: "capability_statements#show"
  post "/", to: "bundles#create"

  # One identical route set per supported FHIR resource type, all dispatched to
  # FhirResourcesController with the type injected via defaults. Kept as literal
  # strings (rather than Fhir::ResourceRegistry.types) so loading routes never
  # autoloads application code at boot. Keep in sync with Fhir::ResourceRegistry.
  %w[Patient MedicationRequest Medication MedicationDispense MedicationAdministration
     MedicationStatement Observation Specimen ImagingStudy DiagnosticReport
     ServiceRequest Practitioner Organization
     PractitionerRole Encounter Location
     Condition AllergyIntolerance Procedure Immunization Coverage].each do |type|
    scope defaults: { resource_type: type } do
      get    "/#{type}",                   to: "fhir_resources#index"
      post   "/#{type}",                   to: "fhir_resources#create"
      put    "/#{type}",                   to: "fhir_resources#conditional_update"
      get    "/#{type}/:id/_history/:vid", to: "fhir_resources#vread"
      get    "/#{type}/:id/_history",      to: "fhir_resources#history"
      get    "/#{type}/:id",               to: "fhir_resources#show"
      put    "/#{type}/:id",               to: "fhir_resources#update"
      delete "/#{type}/:id",               to: "fhir_resources#destroy"
    end
  end
end
