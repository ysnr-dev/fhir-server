namespace :fhir do
  desc "Register a SMART Backend Services client. Usage: rake 'fhir:register_client[my-mcp-server,system/*.read]'"
  task :register_client, %i[name scopes] => :environment do |_task, args|
    name = args[:name].presence || ENV["NAME"]
    scopes = (args[:scopes].presence || ENV["SCOPES"] || "system/*.read").split

    abort "NAME is required (rake 'fhir:register_client[name,scopes]')" if name.blank?
    invalid = scopes.reject { |scope| Fhir::Scopes.valid?(scope) }
    abort "Invalid scope(s): #{invalid.join(', ')} (expected e.g. system/*.read, system/Patient.write)" if invalid.any?

    client, secret = OauthClient.register(name: name, scopes: scopes.join(" "))

    puts "Registered OAuth client '#{client.name}'."
    puts "The secret is shown ONCE -- store it now."
    puts
    puts "  client_id:     #{client.id}"
    puts "  client_secret: #{secret}"
    puts "  scopes:        #{client.scopes}"
  end
end
