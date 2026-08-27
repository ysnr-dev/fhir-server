require "rails_helper"

RSpec.describe "Composition", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "create" do
    it "creates a valid composition with 201" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Composition"])
    end

    it "returns 422 when status is missing or invalid" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id).except("status"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/Composition", params: valid_composition_payload(subject_id: patient_id, status: "draft"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when author is missing" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id).except("author"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when the subject references a non-existent Patient" do
      post "/Composition", params: valid_composition_payload(subject_id: "does-not-exist"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "read / update / delete lifecycle" do
    it "supports the full instance lifecycle" do
      patient_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Composition/#{id}"
      expect(response).to have_http_status(:ok)

      put "/Composition/#{id}", params: valid_composition_payload(subject_id: patient_id, status: "amended"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Composition/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Composition/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "search" do
    it "finds compositions by patient, status, type, category, and date" do
      patient_id = create_patient
      other_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json
      post "/Composition", params: valid_composition_payload(subject_id: other_id, status: "preliminary"), as: :json

      get "/Composition?patient=#{patient_id}"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Composition?status=final"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Composition?type=18842-5"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/Composition?category=11488-4"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/Composition?date=ge2026-07-01&date=le2026-08-01"
      expect(JSON.parse(response.body)["total"]).to eq(2)
    end

    it "finds compositions by identifier" do
      patient_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

      get "/Composition?identifier=http://example.org/composition|COMP1"
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # POS/POMR のカルテを 1 つのプロブレムで縦に読むための絞り込み。対象疾患は
    # C-CDA on FHIR Progress Note の problems_section (LOINC 11450-4) の entry に
    # 入るので、R4 標準の entry で引く。section[] の中の entry[] という配列の二重
    # ネストなので、containment が段を跨いで効いていることをここで固定する。
    describe "entry" do
      def problems_section(*condition_ids)
        {
          "title" => "プロブレム",
          "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "11450-4" }] },
          "entry" => condition_ids.map { |cid| { "reference" => "Condition/#{cid}" } }
        }
      end

      def body_section
        {
          "title" => "主観的情報(S)",
          "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "61150-9" }] },
          "text" => { "status" => "additional", "div" => "<div xmlns=\"http://www.w3.org/1999/xhtml\">咳が続く</div>" }
        }
      end

      def create_with_sections(patient_id, sections)
        post "/Composition",
             params: valid_composition_payload(subject_id: patient_id).merge("section" => sections),
             as: :json
        expect(response).to have_http_status(:created)
        JSON.parse(response.body)["id"]
      end

      def found_ids
        JSON.parse(response.body)["entry"].to_a.map { |e| e["resource"]["id"] }
      end

      it "finds the notes written against one problem" do
        patient_id = create_patient
        target_id = create_with_sections(patient_id, [problems_section("c1"), body_section])
        create_with_sections(patient_id, [problems_section("c2"), body_section])

        get "/Composition", params: { entry: "Condition/c1" }

        expect(found_ids).to eq([target_id])
      end

      it "qualifies a bare id as a Condition" do
        patient_id = create_patient
        target_id = create_with_sections(patient_id, [problems_section("c1")])

        get "/Composition", params: { entry: "c1" }

        expect(found_ids).to eq([target_id])
      end

      # カンマは OR。親プロブレムを選ぶと下位プロブレムの記録も並べて引くため。
      it "ORs comma-separated references" do
        patient_id = create_patient
        first_id = create_with_sections(patient_id, [problems_section("c1")])
        second_id = create_with_sections(patient_id, [problems_section("c2")])
        create_with_sections(patient_id, [problems_section("c3")])

        get "/Composition", params: { patient: patient_id, entry: "Condition/c1,Condition/c2" }

        expect(found_ids).to match_array([first_id, second_id])
      end

      # 内側の配列のメンバーシップ(1 セクションに複数 entry)。
      it "matches any entry of the same section" do
        patient_id = create_patient
        target_id = create_with_sections(patient_id, [problems_section("c1", "c2")])

        get "/Composition", params: { entry: "Condition/c2" }

        expect(found_ids).to eq([target_id])
      end

      # 外側の配列のメンバーシップ(entry を持つセクションと持たないセクションの併存)。
      it "looks past sections that carry no entry" do
        patient_id = create_patient
        target_id = create_with_sections(patient_id, [body_section, problems_section("c1")])

        get "/Composition", params: { entry: "Condition/c1" }

        expect(found_ids).to eq([target_id])
      end

      # containment は構造ごと突き合わせるので、同じ参照が別の場所にあっても拾わない。
      it "ignores the same reference held outside section.entry" do
        patient_id = create_patient
        post "/Composition",
             params: valid_composition_payload(subject_id: patient_id).merge(
               "extension" => [{
                 "url" => "http://fhir-client.local/StructureDefinition/some-other-reference",
                 "valueReference" => { "reference" => "Condition/c1" }
               }]
             ),
             as: :json
        expect(response).to have_http_status(:created)

        get "/Composition", params: { entry: "Condition/c1" }

        expect(JSON.parse(response.body)["total"]).to eq(0)
      end

      # section キーの有無で判定すると、entry を持たない本文セクションだけの記録まで
      # 「entry あり」に数えてしまう。既定ペイロードがまさにその形。
      it "supports entry:missing" do
        patient_id = create_patient
        linked_id = create_with_sections(patient_id, [problems_section("c1"), body_section])
        unlinked_id = create_with_sections(patient_id, [body_section])

        get "/Composition", params: { patient: patient_id, "entry:missing" => "true" }
        expect(found_ids).to eq([unlinked_id])

        get "/Composition", params: { patient: patient_id, "entry:missing" => "false" }
        expect(found_ids).to eq([linked_id])
      end

      it "chains into the Condition (entry.code)" do
        patient_id = create_patient
        post "/Condition", params: valid_condition_payload(subject_id: patient_id), as: :json
        condition_id = JSON.parse(response.body)["id"]
        target_id = create_with_sections(patient_id, [problems_section(condition_id)])
        create_with_sections(patient_id, [problems_section("c2")])

        get "/Composition", params: { "entry.code" => "J20.9" }
        expect(found_ids).to eq([target_id])

        get "/Composition", params: { "entry:Condition.code" => "J20.9" }
        expect(found_ids).to eq([target_id])
      end

      # 逆向き。Condition 側から「この病名で書かれた記録があるか」を引く。
      it "is reachable from the Condition side (_has)" do
        patient_id = create_patient
        post "/Condition", params: valid_condition_payload(subject_id: patient_id), as: :json
        condition_id = JSON.parse(response.body)["id"]
        create_with_sections(patient_id, [problems_section(condition_id)])
        post "/Condition", params: valid_condition_payload(subject_id: patient_id), as: :json
        expect(response).to have_http_status(:created)

        get "/Condition", params: { "_has:Composition:entry:status" => "final" }

        expect(found_ids).to eq([condition_id])
      end
    end
  end

  it "joins the patient compartment ($everything)" do
    patient_id = create_patient
    post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

    get "/Patient/#{patient_id}/$everything"

    types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
    expect(types).to contain_exactly("Patient", "Composition")
  end
end
