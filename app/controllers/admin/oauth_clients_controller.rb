module Admin
  # OAuthクライアントの一覧・登録・削除。これまで rake fhir:register_client /
  # fhir:register_launch_client でしか登録できず、削除の手段が存在しなかった。
  #
  # 登録の実体は OauthClient.register で、そこがバックエンド用と対話型launch用の
  # 排他性(system/ と patient/ を混ぜない等)を担保している。このコントローラの
  # 仕事は「JSONの型エラーを400、意味エラーを422に振り分ける」ことだけで、
  # 検証ロジックを二重に持たない -- 持てばいずれ矛盾する。
  class OauthClientsController < BaseController
    # GET /admin/oauth_clients
    def index
      clients = OauthClient.order(created_at: :desc).to_a
      access_counts = active_token_counts(AccessToken, clients)
      refresh_counts = active_token_counts(RefreshToken, clients)

      # 件数は数十のオーダーなのでページングは入れていない。必要になったら
      # ここに Master::BaseController#paginate 相当を挟む(形は total/items で同じ)。
      render json: {
        total: clients.size,
        items: clients.map do |client|
          client_json(client,
                      access_token_count: access_counts.fetch(client.id, 0),
                      refresh_token_count: refresh_counts.fetch(client.id, 0))
        end
      }
    end

    # POST /admin/oauth_clients
    def create
      attributes, error = registration_attributes
      return render_invalid_request(error) if error

      invalid_uris = attributes[:redirect_uris].reject { |uri| absolute_uri?(uri) }
      if invalid_uris.any?
        # rake fhir:register_launch_client と同じ判定。相対URIは「意味として」
        # 不正なので 422。モデルに置かないのは rake の挙動を変えないため。
        return render_validation_errors(["redirect_uris must be absolute URIs: #{invalid_uris.join(', ')}"])
      end

      client, secret = OauthClient.register(**attributes)
      @created_client_id = client.id
      # 生シークレットが現れるのはこのレスポンスだけ。JWKS/publicクライアントでは
      # キー自体が存在しないことが「シークレットは無い」の信号になる。
      render json: client_json(client, secret: secret), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render_validation_errors(e.record.errors.full_messages)
    end

    # DELETE /admin/oauth_clients/:id
    def destroy
      client = OauthClient.find_by(id: params[:id])
      return render_not_found("No such OAuth client: #{params[:id]}") unless client

      @deleted_client_id = client.id
      # dependent: :delete_all のカスケードは件数を返さないので、消す前に数える。
      summary = dependent_counts(client)
      client.destroy!

      render json: { client_id: client.id, name: client.name, deleted: summary }
    end

    private

    # --- 監査 ----------------------------------------------------------------

    def audit_interaction
      case action_name
      when "index" then "search-type"
      when "create" then "create"
      when "destroy" then "delete"
      end
    end

    def audit_resource_type
      "OauthClient"
    end

    def audit_resource_id
      @created_client_id || @deleted_client_id || params[:id]
    end

    # --- リクエストの解釈 ----------------------------------------------------

    # 形(バックエンド用 / 対話型launch用)は「存在するフィールド」から導出する。
    # OauthClient.register が既にそうしているので、kind のような判別フィールドを
    # 足すと検証が二重になる。
    #
    # Returns [attributes, nil] or [nil, error_description].
    def registration_attributes
      scopes, error = normalized_scopes
      return [nil, error] if error

      redirect_uris, error = normalized_redirect_uris
      return [nil, error] if error

      jwks, error = normalized_jwks
      return [nil, error] if error

      client_type = params[:client_type].presence || "confidential"
      return [nil, "client_type must be a string"] unless client_type.is_a?(String)

      [{ name: params[:name].to_s.strip, scopes: scopes.join(" "), jwks: jwks,
         redirect_uris: redirect_uris, client_type: client_type }, nil]
    end

    def normalized_scopes
      raw = params[:scopes]
      case raw
      when nil then [[], nil]
      when String then [raw.split, nil]
      when Array
        return [nil, "scopes must be an array of strings"] unless raw.all?(String)

        [raw.flat_map(&:split), nil]
      else
        [nil, "scopes must be an array of strings"]
      end
    end

    def normalized_redirect_uris
      raw = params[:redirect_uris]
      case raw
      when nil then [[], nil]
      when String then [raw.split(",").map(&:strip).reject(&:blank?), nil]
      when Array
        return [nil, "redirect_uris must be an array of strings"] unless raw.all?(String)

        [raw.map(&:strip).reject(&:blank?), nil]
      else
        [nil, "redirect_uris must be an array of strings"]
      end
    end

    def normalized_jwks
      raw = params[:jwks]
      return [nil, nil] if raw.blank?

      # ActionController::Parameters で来るので to_unsafe_h で素のHashに戻す
      # (permit は使わない -- JWKSのキー構成をこちらで規定したくない)。
      jwks = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      unless jwks.is_a?(Hash) && jwks["keys"].is_a?(Array)
        return [nil, "jwks must be an object containing a 'keys' array"]
      end

      [jwks, nil]
    end

    def absolute_uri?(value)
      URI.parse(value).absolute?
    rescue URI::InvalidURIError
      false
    end

    # --- レスポンスの組み立て ------------------------------------------------

    # 「秘密を漏らさない」を一箇所に集約する。secret_digest と JWKS 本体は
    # どのレスポンスにも出さない(JWKSは公開鍵なので無害だが、UIが使わない)。
    def client_json(client, secret: nil, access_token_count: nil, refresh_token_count: nil)
      json = {
        client_id: client.id,
        name: client.name,
        client_type: client.client_type,
        scopes: client.allowed_scopes,
        redirect_uris: client.redirect_uri_list,
        kind: client.launch_client? ? "launch" : "backend",
        auth_method: auth_method(client),
        jwks_key_count: client.jwks&.dig("keys")&.size.to_i,
        created_at: client.created_at.utc.iso8601,
        updated_at: client.updated_at.utc.iso8601
      }
      json[:active_access_token_count] = access_token_count unless access_token_count.nil?
      json[:active_refresh_token_count] = refresh_token_count unless refresh_token_count.nil?
      json[:client_secret] = secret if secret
      json
    end

    def auth_method(client)
      return "private_key_jwt" if client.jwks.present?
      return "client_secret" if client.secret_digest.present?

      "none" # public client: PKCE が所有証明の代わり
    end

    def active_token_counts(model, clients)
      return {} if clients.empty?

      model.where(oauth_client_id: clients.map(&:id), revoked_at: nil)
           .where(expires_at: Time.current..)
           .group(:oauth_client_id).count
    end

    def dependent_counts(client)
      {
        access_tokens: client.access_tokens.count,
        refresh_tokens: client.refresh_tokens.count,
        authorization_codes: client.authorization_codes.count,
        client_assertion_jtis: client.client_assertion_jtis.count,
        bulk_exports_detached: client.bulk_exports.count
      }
    end
  end
end
