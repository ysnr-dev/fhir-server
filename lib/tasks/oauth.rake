namespace :fhir do
  desc "Register a SMART Backend Services client. Usage: rake 'fhir:register_client[my-mcp-server,system/*.read]' " \
       "(pass a JWKS file as the third arg for private_key_jwt clients)"
  task :register_client, %i[name scopes jwks_path] => :environment do |_task, args|
    name = args[:name].presence || ENV["NAME"]
    scopes = (args[:scopes].presence || ENV["SCOPES"] || "system/*.read").split
    jwks_path = args[:jwks_path].presence || ENV["JWKS_FILE"]

    abort "NAME is required (rake 'fhir:register_client[name,scopes]')" if name.blank?
    # Backend clients take system scopes only -- a patient/ scope here would be
    # a launch client registered through the wrong task, and it would get a
    # token with no patient context to filter against.
    invalid = scopes.reject { |scope| Fhir::Scopes.valid_system?(scope) }
    abort "Invalid scope(s): #{invalid.join(', ')} (expected e.g. system/*.read, system/Patient.write; " \
          "use fhir:register_launch_client for patient/ scopes)" if invalid.any?

    jwks = nil
    if jwks_path
      jwks = JSON.parse(File.read(jwks_path))
      abort "JWKS file must contain a 'keys' array" unless jwks.is_a?(Hash) && jwks["keys"].is_a?(Array)
    end

    client, secret = OauthClient.register(name: name, scopes: scopes.join(" "), jwks: jwks)

    puts "Registered OAuth client '#{client.name}'."
    puts
    puts "  client_id:     #{client.id}"
    if secret
      puts "  client_secret: #{secret}  (shown ONCE -- store it now)"
    else
      puts "  auth method:   private_key_jwt (#{jwks['keys'].size} key(s) registered)"
    end
    puts "  scopes:        #{client.scopes}"
  end

  desc "Register an interactive SMART launch client (authorization_code + PKCE). Usage: " \
       "rake 'fhir:register_launch_client[my-app,https://app.example/callback,patient/*.read,public]'"
  task :register_launch_client, %i[name redirect_uris scopes client_type] => :environment do |_task, args|
    name = args[:name].presence || ENV["NAME"]
    redirect_uris = (args[:redirect_uris].presence || ENV["REDIRECT_URIS"]).to_s.split(",").map(&:strip).reject(&:blank?)
    scopes = (args[:scopes].presence || ENV["SCOPES"] || "patient/*.read").split
    client_type = args[:client_type].presence || ENV["CLIENT_TYPE"] || "public"

    abort "NAME is required" if name.blank?
    abort "REDIRECT_URIS is required (comma-separated)" if redirect_uris.empty?

    invalid_uris = redirect_uris.reject { |uri| URI.parse(uri).absolute? rescue false }
    abort "redirect_uri(s) must be absolute URIs: #{invalid_uris.join(', ')}" if invalid_uris.any?

    invalid = scopes.reject { |scope| Fhir::Scopes.valid_patient?(scope) || Fhir::Scopes.valid_context?(scope) }
    abort "Invalid scope(s): #{invalid.join(', ')} " \
          "(expected e.g. patient/*.read, patient/Observation.read, offline_access, openid, fhirUser)" if invalid.any?

    client, secret = OauthClient.register(
      name: name, scopes: scopes.join(" "), redirect_uris: redirect_uris, client_type: client_type
    )

    puts "Registered launch client '#{client.name}'."
    puts
    puts "  client_id:     #{client.id}"
    puts "  client_secret: #{secret}  (shown ONCE -- store it now)" if secret
    puts "  client_type:   #{client.client_type}#{' (no secret; PKCE only)' if client.public_client?}"
    puts "  redirect_uris: #{client.redirect_uri_list.join(', ')}"
    puts "  scopes:        #{client.scopes}"
  end

  desc "Create a patient-facing account for the interactive launch. Usage: " \
       "rake 'fhir:register_user[patient@example.com,<patient-id>,山田太郎]' (PASSWORD env optional)"
  task :register_user, %i[email patient_id name] => :environment do |_task, args|
    email = args[:email].presence || ENV["EMAIL"]
    patient_id = args[:patient_id].presence || ENV["PATIENT_ID"]
    name = args[:name].presence || ENV["USER_NAME"]

    abort "EMAIL is required" if email.blank?
    abort "PATIENT_ID is required" if patient_id.blank?

    patient = Patient.find_by(id: patient_id, deleted: false)
    abort "No such Patient: #{patient_id}" unless patient

    password = ENV["PASSWORD"].presence || SecureRandom.urlsafe_base64(12)
    user = User.create!(email: email, patient_id: patient.id, name: name, password: password)

    puts "Registered user '#{user.email}' for Patient/#{user.patient_id}."
    puts
    puts "  password:      #{password}#{'  (generated, shown ONCE -- store it now)' unless ENV['PASSWORD'].present?}"
  end
end
