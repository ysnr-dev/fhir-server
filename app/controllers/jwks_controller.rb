# GET /.well-known/jwks.json -- the public half of the id_token signing key,
# so clients (and Inferno-style test suites) can verify the OpenID Connect
# id_tokens this server issues. Always public, like the other discovery
# documents; cacheable since the key is stable.
class JwksController < ApplicationController
  def show
    response.set_header("Cache-Control", "public, max-age=3600")
    render json: Fhir::SigningKey.jwks
  end
end
