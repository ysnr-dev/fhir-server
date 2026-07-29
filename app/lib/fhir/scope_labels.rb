module Fhir
  # スコープの日本語ラベル。対話型launchの同意画面(Oauth::BrowserController)と
  # 管理APIのスコープ選択肢(Admin::ScopesController)で共有する。
  #
  # 同意は「情報を与えられた上での同意」でなければならず、"patient/Observation.read"
  # は患者が読めるものではない。管理画面側も同じ理由で、生のスコープ文字列だけを
  # 並べるとタイポと誤選択の温床になる。
  #
  # RESOURCE のキーは Fhir::ResourceRegistry.types を網羅すること
  # (spec/lib/fhir/scope_labels_spec.rb が保証する)。
  module ScopeLabels
    RESOURCE = {
      "*" => "すべての診療記録",
      "Patient" => "患者基本情報",
      "Observation" => "検査・バイタルの記録",
      "Condition" => "傷病名",
      "MedicationRequest" => "処方",
      "MedicationDispense" => "調剤",
      "MedicationStatement" => "服薬状況",
      "MedicationAdministration" => "投薬の実施記録",
      "Medication" => "医薬品情報",
      "AllergyIntolerance" => "アレルギー情報",
      "Immunization" => "予防接種歴",
      "Procedure" => "処置・手術",
      "Encounter" => "受診歴",
      "DiagnosticReport" => "検査レポート",
      "DocumentReference" => "文書",
      "Coverage" => "保険情報",
      "ServiceRequest" => "検査・処置の依頼",
      "Specimen" => "検体",
      "ImagingStudy" => "画像検査",
      "Questionnaire" => "問診票・診療テンプレート",
      "QuestionnaireResponse" => "問診・テンプレートの回答",
      "Composition" => "診療文書",
      "Practitioner" => "医療従事者",
      "PractitionerRole" => "医療従事者の役割",
      "Organization" => "組織・医療機関",
      "Location" => "場所・施設",
      "Binary" => "添付ファイルの実体"
    }.freeze

    # コンテキストスコープは何かの「閲覧」ではない -- リフレッシュ系はアプリが
    # アクセスを保持する期間を、ID系はアプリに自分が誰であるかを伝える。
    # どちらも患者が平易に理解できる表現にする。
    CONTEXT = {
      "offline_access" => "ログアウト後も再ログインなしでアクセスを継続する(長期間)",
      "online_access" => "ログイン中のあいだアクセスを継続する",
      "openid" => "あなたがログイン本人であることの確認",
      "fhirUser" => "ログイン中の患者情報とのひも付け",
      "profile" => "ログイン中の患者情報とのひも付け"
    }.freeze

    # SMART v1 のアクセス種別。v2 の CRUDS 文字列はUIには出さない
    # (Fhir::Scopes は受理するが、選択肢として並べても意味が伝わらない)。
    ACCESS = {
      "read" => "参照",
      "write" => "更新",
      "*" => "参照・更新"
    }.freeze

    module_function

    # 未知の型は生の型名にフォールバックする。ラベル漏れでも画面が壊れないため。
    def resource(type)
      RESOURCE.fetch(type, type)
    end

    def context(scope)
      CONTEXT[scope]
    end

    def access(value)
      ACCESS.fetch(value, value)
    end
  end
end
