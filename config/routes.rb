Rails.application.routes.draw do
  # LB用ヘルスチェック(認証・監査・SSL/Host検査の対象外)
  get "/up", to: "health#show"

  # 管理API: OAuthクライアントの登録・削除。FHIRのスコープではなく専用の共有
  # トークン FHIR_ADMIN_TOKEN で認証する(未設定なら常に503 = fail closed)。
  # ブラウザから直接叩く想定はない -- CORSは意図的に無効なので、管理UIを持つ
  # 別アプリ(fhir-client)の backend がサーバー間で中継する。
  namespace :admin do
    resources :oauth_clients, only: %i[index create destroy]
    get "scopes", to: "scopes#show"
  end

  get "/metadata", to: "capability_statements#show"
  get "/.well-known/smart-configuration", to: "smart_configurations#show"
  get "/.well-known/jwks.json", to: "jwks#show"
  post "/oauth/token", to: "oauth_tokens#create"
  post "/oauth/revoke", to: "oauth_revocations#create"
  post "/oauth/introspect", to: "oauth_introspections#create"

  # Interactive SMART standalone launch. The only HTML in this app; everything
  # under it renders login/consent and returns the user to the client app.
  get  "/oauth/authorize", to: "oauth/browser#authorize", as: :oauth_authorize
  post "/oauth/login",     to: "oauth/browser#login",     as: :oauth_login
  post "/oauth/consent",   to: "oauth/browser#consent",   as: :oauth_consent
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
  # The cohort id is :group_id rather than :id so it can never be confused with
  # the export/file id that status / cancel / download read out of params[:id].
  match "/Group/:group_id/$export", to: "bulk_exports#kickoff", via: %i[get post], defaults: { kind: "group" }
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
     Questionnaire QuestionnaireResponse
     Composition DocumentReference Binary
     Device RelatedPerson Group].each do |type|
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
