module Admin
  # EHR launch の起動文脈(LaunchContext)の発行。
  #
  # 呼び出し元はカルテ(fhir-client)の backend で、ログイン中の医療者と開いている
  # 患者・受診を名乗って launch トークンを求める。「その医療者が本当にログイン
  # 中か」はこのサーバーには確かめようがなく、管理トークンを持つ中継を信頼する
  # 設計 -- だからこそ Backend Services のスコープではなく管理 API に置く
  # (system/*.* を持つだけの B2B クライアントが他人の身元を名乗れてはならない)。
  #
  # 患者・医療者・受診の実在はここで確認する。authorize の時点で確認しても遅く
  # (アプリ側のエラーになる)、発行側で 422 を返す方が原因が伝わる。
  class LaunchContextsController < BaseController
    # POST /admin/launch_contexts
    def create
      attributes, error = launch_attributes
      return render_invalid_request(error) if error

      client = OauthClient.find_by(id: attributes[:client_id])
      return render_not_found("No such OAuth client: #{attributes[:client_id]}") unless client

      problems = context_problems(client, attributes)
      return render_validation_errors(problems) if problems.any?

      context, raw = LaunchContext.issue(
        client: client,
        patient_id: attributes[:patient_id],
        encounter_id: attributes[:encounter_id],
        practitioner_id: attributes[:practitioner_id],
        need_patient_banner: attributes[:need_patient_banner],
        issued_by: attributes[:issued_by],
        app_context: attributes[:app_context]
      )
      @launch_context_id = context.id

      # 生の launch トークンが現れるのはこのレスポンスだけ。
      render json: {
        launch: raw,
        expires_in: LaunchContext::TTL.to_i,
        expires_at: context.expires_at.utc.iso8601,
        client_id: client.id,
        patient_id: context.patient_id,
        encounter_id: context.encounter_id,
        practitioner_id: context.practitioner_id
      }.compact, status: :created
    end

    private

    def audit_interaction
      "create"
    end

    def audit_resource_type
      "LaunchContext"
    end

    def audit_resource_id
      @launch_context_id&.to_s
    end

    # Returns [attributes, nil] or [nil, error_description]. 型の誤りだけを見る
    # (意味の誤りは context_problems で 422)。
    def launch_attributes
      strings = {}
      %i[client_id patient_id encounter_id practitioner_id issued_by].each do |key|
        value = params[key]
        return [nil, "#{key} must be a string"] unless value.nil? || value.is_a?(String)

        strings[key] = value.to_s.strip.presence
      end

      # appContext は中身に立ち入らない(アプリとサービスの間の取り決め)。型と長さだけ見る。
      app_context = params[:app_context]
      return [nil, "app_context must be a string"] unless app_context.nil? || app_context.is_a?(String)
      return [nil, "app_context is too long"] if app_context.to_s.bytesize > LaunchContext::APP_CONTEXT_MAX_BYTES

      strings[:app_context] = app_context.presence

      banner = params[:need_patient_banner]
      return [nil, "need_patient_banner must be a boolean"] unless banner.nil? || [true, false].include?(banner)

      %i[client_id patient_id practitioner_id].each do |key|
        return [nil, "#{key} is required"] if strings[key].blank?
      end

      [strings.merge(need_patient_banner: banner == true), nil]
    end

    def context_problems(client, attributes)
      problems = []
      problems << "client is not registered for EHR launch (scope 'launch' is required)" unless client.ehr_launchable?
      problems << "patient_id does not exist" unless live?(Patient, attributes[:patient_id])
      problems << "practitioner_id does not exist" unless live?(Practitioner, attributes[:practitioner_id])

      if attributes[:encounter_id]
        encounter = Encounter.find_by(id: attributes[:encounter_id], deleted: false)
        if encounter.nil?
          problems << "encounter_id does not exist"
        elsif encounter.subject_reference != "Patient/#{attributes[:patient_id]}"
          problems << "encounter_id does not belong to patient_id"
        end
      end

      problems
    end

    def live?(model, id)
      model.exists?(id: id, deleted: false)
    end
  end
end
