require "rails_helper"

RSpec.describe "DiagnosticReports", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /DiagnosticReport" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/DiagnosticReport/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("DiagnosticReport")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_DiagnosticReport_Common"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when code is missing" do
      subject_id = create_patient

      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id).except("code"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /DiagnosticReport/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/DiagnosticReport/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/DiagnosticReport/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/DiagnosticReport/#{id}",
          params: valid_diagnostic_report_payload(subject_id: subject_id, status: "amended"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/DiagnosticReport/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/DiagnosticReport/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /DiagnosticReport (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id), as: :json

      get "/DiagnosticReport", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by code" do
      subject_id = create_patient
      post "/DiagnosticReport", params: valid_diagnostic_report_payload(subject_id: subject_id), as: :json

      get "/DiagnosticReport", params: { code: "58410-2" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "finds by result reference (Observation containment)" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      observation_id = JSON.parse(response.body)["id"]
      post "/DiagnosticReport",
           params: valid_diagnostic_report_payload(
             subject_id: subject_id,
             result: [{ "reference" => "Observation/#{observation_id}" }]
           ),
           as: :json

      get "/DiagnosticReport", params: { result: "Observation/#{observation_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    describe "_include" do
      it "includes the referenced Observation via DiagnosticReport:result" do
        subject_id = create_patient
        post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
        observation_id = JSON.parse(response.body)["id"]
        post "/DiagnosticReport",
             params: valid_diagnostic_report_payload(
               subject_id: subject_id,
               result: [{ "reference" => "Observation/#{observation_id}" }]
             ),
             as: :json
        id = JSON.parse(response.body)["id"]

        get "/DiagnosticReport", params: { _id: id, _include: "DiagnosticReport:result" }

        bundle = JSON.parse(response.body)
        included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
        expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Observation"])
        expect(included.first["resource"]["id"]).to eq(observation_id)
      end

      it "includes the referenced Specimen via DiagnosticReport:specimen" do
        subject_id = create_patient
        post "/Specimen", params: valid_specimen_payload(subject_id: subject_id), as: :json
        specimen_id = JSON.parse(response.body)["id"]
        post "/DiagnosticReport",
             params: valid_diagnostic_report_payload(
               subject_id: subject_id,
               specimen: [{ "reference" => "Specimen/#{specimen_id}" }]
             ),
             as: :json
        id = JSON.parse(response.body)["id"]

        get "/DiagnosticReport", params: { _id: id, _include: "DiagnosticReport:specimen" }

        bundle = JSON.parse(response.body)
        included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
        expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Specimen"])
        expect(included.first["resource"]["id"]).to eq(specimen_id)
      end
    end

    # 検査結果(DiagnosticReport)と、その元になった検体検査オーダー(ServiceRequest)。
    describe "based-on (結果の元になったオーダー)" do
      # オーダー 2 件を作り、片方にだけ結果を付ける。
      def create_order_with_report(subject_id)
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
        resulted_id = JSON.parse(response.body)["id"]
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
        pending_id = JSON.parse(response.body)["id"]
        post "/DiagnosticReport",
             params: valid_diagnostic_report_payload(
               subject_id: subject_id, basedOn: [{ "reference" => "ServiceRequest/#{resulted_id}" }]
             ),
             as: :json
        [resulted_id, pending_id, JSON.parse(response.body)["id"]]
      end

      def entry_ids(mode)
        JSON.parse(response.body)["entry"].to_a
            .select { |entry| entry.dig("search", "mode") == mode }
            .map { |entry| entry.dig("resource", "id") }
      end

      it "finds the report of an order" do
        subject_id = create_patient
        resulted_id, _pending_id, report_id = create_order_with_report(subject_id)

        get "/DiagnosticReport", params: { "based-on" => "ServiceRequest/#{resulted_id}" }

        expect(JSON.parse(response.body)["total"]).to eq(1)
        expect(entry_ids("match")).to eq([report_id])
      end

      # 「まだ結果の付いていないオーダー」を選ばせるため、オーダーの検索に
      # 結果を添えてもらう(結果が付いた方だけ include に現れる)。
      it "includes the reports of the matched orders with _revinclude=DiagnosticReport:based-on" do
        subject_id = create_patient
        resulted_id, pending_id, report_id = create_order_with_report(subject_id)

        get "/ServiceRequest",
            params: { subject: "Patient/#{subject_id}", _revinclude: "DiagnosticReport:based-on" }

        expect(entry_ids("match")).to contain_exactly(resulted_id, pending_id)
        expect(entry_ids("include")).to eq([report_id])
      end

      # 検査結果の登録画面は「オーダーの明細(ラベル用)」と「結果の有無」を
      # 1 リクエストで欲しいので、2 種類の _revinclude を同時に使う。
      it "combines with _revinclude:iterate=ServiceRequest:based-on" do
        subject_id = create_patient
        resulted_id, pending_id, report_id = create_order_with_report(subject_id)
        post "/ServiceRequest",
             params: valid_service_request_payload(
               subject_id: subject_id, basedOn: [{ "reference" => "ServiceRequest/#{resulted_id}" }]
             ),
             as: :json
        item_id = JSON.parse(response.body)["id"]

        get "/ServiceRequest",
            params: {
              subject: "Patient/#{subject_id}", "based-on:missing" => "true",
              "_revinclude:iterate" => "ServiceRequest:based-on",
              _revinclude: "DiagnosticReport:based-on"
            }

        expect(entry_ids("match")).to contain_exactly(resulted_id, pending_id)
        expect(entry_ids("include")).to contain_exactly(item_id, report_id)
      end

      it "resolves the order with _include=DiagnosticReport:based-on" do
        subject_id = create_patient
        resulted_id, _pending_id, report_id = create_order_with_report(subject_id)

        get "/DiagnosticReport", params: { _id: report_id, _include: "DiagnosticReport:based-on" }

        expect(entry_ids("match")).to eq([report_id])
        expect(entry_ids("include")).to eq([resulted_id])
      end
    end
  end
end
