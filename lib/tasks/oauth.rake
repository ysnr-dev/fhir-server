namespace :fhir do
  desc "Register a SMART Backend Services client. Usage: rake 'fhir:register_client[my-mcp-server,system/*.read]' " \
       "(pass a JWKS file as the third arg for private_key_jwt clients)"
  task :register_client, %i[name scopes jwks_path] => :environment do |_task, args|
    name = args[:name].presence || ENV["NAME"]
    scopes = (args[:scopes].presence || ENV["SCOPES"] || "system/*.read").split
    jwks_path = args[:jwks_path].presence || ENV["JWKS_FILE"]

    abort "NAME is required (rake 'fhir:register_client[name,scopes]')" if name.blank?
    invalid = scopes.reject { |scope| Fhir::Scopes.valid?(scope) }
    abort "Invalid scope(s): #{invalid.join(', ')} (expected e.g. system/*.read, system/Patient.write)" if invalid.any?

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
end
