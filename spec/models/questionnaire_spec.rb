require "rails_helper"

RSpec.describe Questionnaire do
  def build_questionnaire(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts url, version, name, title, status, subjectType, publisher, code, and date" do
      questionnaire = build_questionnaire(
        "url" => "http://example.org/Questionnaire/example",
        "version" => "1.0.0",
        "name" => "ExampleQ",
        "title" => "問診票サンプル",
        "status" => "active",
        "subjectType" => %w[Patient Practitioner],
        "publisher" => "サンプル病院",
        "code" => [{ "system" => "http://loinc.org", "code" => "72166-2" }],
        "date" => "2026-07-29T10:00:00+09:00"
      )

      questionnaire.sync_search_fields!

      expect(questionnaire.url).to eq("http://example.org/Questionnaire/example")
      expect(questionnaire.version).to eq("1.0.0")
      expect(questionnaire.name).to eq("ExampleQ")
      expect(questionnaire.title).to eq("問診票サンプル")
      expect(questionnaire.status).to eq("active")
      expect(questionnaire.subject_type).to eq("Patient")
      expect(questionnaire.publisher).to eq("サンプル病院")
      expect(questionnaire.code_value).to eq("72166-2")
      expect(questionnaire.questionnaire_date).to eq(Time.iso8601("2026-07-29T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      questionnaire = build_questionnaire({})

      expect { questionnaire.sync_search_fields! }.not_to raise_error
      expect(questionnaire.url).to be_nil
      expect(questionnaire.status).to be_nil
      expect(questionnaire.code_value).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits a row per subjectType and per code coding" do
      questionnaire = build_questionnaire(
        "status" => "active",
        "version" => "1.0.0",
        "subjectType" => %w[Patient Practitioner],
        "code" => [
          { "system" => "http://loinc.org", "code" => "72166-2" },
          { "system" => "http://example.org/local", "code" => "LOCAL-1" }
        ]
      )

      questionnaire.save!(validate: false)
      questionnaire.sync_tokens!

      expect(questionnaire.resource_tokens.where(param_name: "subject-type").pluck(:code))
        .to contain_exactly("Patient", "Practitioner")
      expect(questionnaire.resource_tokens.where(param_name: "code").pluck(:system, :code))
        .to contain_exactly(["http://loinc.org", "72166-2"], ["http://example.org/local", "LOCAL-1"])
      expect(questionnaire.resource_tokens.where(param_name: "version").pluck(:code)).to eq(["1.0.0"])
    end
  end
end
