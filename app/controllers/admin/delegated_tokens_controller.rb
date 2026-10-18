module Admin
  # CDS Hooks の fhirAuthorization に載せる短命トークンの発行。
  #
  # 呼び出し元はカルテ(fhir-client)の backend で、hook を呼ぶ直前にログイン中の医療者を名乗って
  # CDS サービス(委任クライアント)向けのトークンを求める。EHR launch の起動文脈と同じく、
  # 「その医療者が本当にログイン中か」は管理トークンを持つ中継を信頼する。
  #
  # 発行するのは登録スコープのうち読み取りだけ(OauthClient#delegated_scopes)、寿命は 5 分。
  class DelegatedTokensController < BaseController
    # POST /admin/delegated_tokens
    def create
      attributes, error = token_attributes
      return render_invalid_request(error) if error

      client = OauthClient.find_by(id: attributes[:client_id])
      return render_not_found("No such OAuth client: #{attributes[:client_id]}") unless client

      problems = token_problems(client, attributes)
      return render_validation_errors(problems) if problems.any?

      scopes = client.delegated_scopes
      record, raw = AccessToken.issue(
        client, scopes: scopes, practitioner_id: attributes[:practitioner_id],
                patient_id: attributes[:patient_id], ttl: AccessToken::DELEGATED_TTL
      )
      @token_id = record.id

      # CDS Hooks 2.0 の fhirAuthorization の形そのまま(subject はサービスの client_id)。
      render json: {
        access_token: raw,
        token_type: "Bearer",
        expires_in: AccessToken::DELEGATED_TTL.to_i,
        scope: scopes.join(" "),
        subject: client.id,
        patient: attributes[:patient_id]
      }.compact, status: :created
    end

    private

    def audit_interaction
      "create"
    end

    def audit_resource_type
      "AccessToken"
    end

    def audit_resource_id
      @token_id&.to_s
    end

    def token_attributes
      attributes = {}
      %i[client_id practitioner_id patient_id].each do |key|
        value = params[key]
        return [nil, "#{key} must be a string"] unless value.nil? || value.is_a?(String)

        attributes[key] = value.to_s.strip.presence
      end
      %i[client_id practitioner_id].each do |key|
        return [nil, "#{key} is required"] if attributes[key].blank?
      end
      [attributes, nil]
    end

    def token_problems(client, attributes)
      problems = []
      problems << "client is not a delegated client (user/ scopes without redirect URIs)" unless client.delegated_client?
      problems << "client has no readable user/ scope" if client.delegated_client? && client.delegated_scopes.empty?
      problems << "practitioner_id does not exist" unless Practitioner.exists?(id: attributes[:practitioner_id], deleted: false)
      if attributes[:patient_id] && !Patient.exists?(id: attributes[:patient_id], deleted: false)
        problems << "patient_id does not exist"
      end
      problems
    end
  end
end
