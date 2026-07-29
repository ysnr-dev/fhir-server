require "rails_helper"

RSpec.describe QuestionnaireValidator do
  ITEM_CONTROL = "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl".freeze
  MAX_OCCURS = "http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs".freeze
  INITIAL_EXPRESSION = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-initialExpression".freeze
  CALCULATED_EXPRESSION = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression".freeze

  def base_payload(**overrides)
    {
      "resourceType" => "Questionnaire",
      "version" => "1.0.0",
      "name" => "ExampleQ",
      "title" => "問診票サンプル",
      "status" => "active",
      "subjectType" => ["Patient"],
      "item" => [
        {
          "linkId" => "group1",
          "type" => "group",
          "item" => [{ "linkId" => "q1", "type" => "string" }]
        }
      ]
    }.merge(overrides)
  end

  def expressions(result)
    result.issues.flat_map { |issue| issue[:expression] }
  end

  # Replaces the single top-level group's children with `children`.
  def with_children(children, parent: {})
    base_payload("item" => [{ "linkId" => "group1", "type" => "group", "item" => children }.merge(parent)])
  end

  it "accepts a minimal valid Questionnaire" do
    expect(described_class.call(base_payload)).to be_valid
  end

  describe "required elements" do
    it "requires version, name, title, status, subjectType, and item" do
      %w[version name title status subjectType item].each do |field|
        expect(described_class.call(base_payload.except(field))).not_to be_valid, "expected #{field} to be required"
      end
    end

    it "rejects an empty item array" do
      expect(described_class.call(base_payload("item" => []))).not_to be_valid
    end

    it "requires linkId and type on every item, including nested ones" do
      result = described_class.call(with_children([{ "type" => "string" }, { "linkId" => "q2" }]))

      expect(result).not_to be_valid
      expect(expressions(result)).to include("Questionnaire.item[0].item[0].linkId",
                                             "Questionnaire.item[0].item[1].type")
    end
  end

  describe "value sets" do
    it "rejects a status outside publication-status" do
      expect(described_class.call(base_payload("status" => "final"))).not_to be_valid
    end

    it "rejects item types JASPEHR excludes from the base item-type set" do
      %w[boolean url attachment reference quantity open-choice].each do |type|
        result = described_class.call(with_children([{ "linkId" => "q1", "type" => type }]))
        expect(result).not_to be_valid, "expected item.type '#{type}' to be rejected"
      end
    end

    it "accepts every item type JASPEHR keeps" do
      Fhir::Terminology::QUESTIONNAIRE_ITEM_TYPE_JASPEHR.each do |type|
        # `choice` needs itemControl (jsp-6), so give every candidate one.
        item = { "linkId" => "q1", "type" => type,
                 "extension" => [{ "url" => ITEM_CONTROL, "valueCodeableConcept" => { "text" => "radio" } }] }
        expect(described_class.call(with_children([item]))).to be_valid, "expected item.type '#{type}' to be accepted"
      end
    end
  end

  describe "JASPEHR invariants" do
    it "jsp-5: rejects a name outside the charset or longer than 15 characters" do
      expect(described_class.call(base_payload("name" => "名前"))).not_to be_valid
      expect(described_class.call(base_payload("name" => "A" * 16))).not_to be_valid
      expect(described_class.call(base_payload("name" => "A" * 15))).to be_valid
    end

    it "jsp-4: rejects a linkId outside the charset" do
      result = described_class.call(with_children([{ "linkId" => "設問1", "type" => "string" }]))

      expect(result).not_to be_valid
      expect(result.issues.map { |i| i[:diagnostics] }.join).to include("jsp-4")
    end

    it "jsp-1: allows enableWhen only on a group" do
      gate = [{ "question" => "group1", "operator" => "=", "answerString" => "yes" }]

      valid = with_children([{ "linkId" => "sub", "type" => "group", "enableWhen" => gate }],
                            parent: { "type" => "choice",
                                      "extension" => [{ "url" => ITEM_CONTROL,
                                                        "valueCodeableConcept" => { "text" => "radio" } }] })
      expect(described_class.call(valid)).to be_valid

      invalid = with_children([{ "linkId" => "sub", "type" => "string", "enableWhen" => gate }],
                              parent: { "type" => "choice",
                                        "extension" => [{ "url" => ITEM_CONTROL,
                                                          "valueCodeableConcept" => { "text" => "radio" } }] })
      expect(described_class.call(invalid)).not_to be_valid
    end

    it "jsp-3: allows repeats only on a group" do
      item = { "linkId" => "q1", "type" => "string", "repeats" => true }
      expect(described_class.call(with_children([item]))).not_to be_valid
    end

    it "jsp-8: rejects enableWhen together with repeats" do
      item = {
        "linkId" => "sub", "type" => "group", "repeats" => true,
        "enableWhen" => [{ "question" => "group1", "operator" => "=", "answerString" => "yes" }],
        "extension" => [{ "url" => MAX_OCCURS, "valueInteger" => 3 }]
      }
      parent = { "type" => "choice",
                 "extension" => [{ "url" => ITEM_CONTROL, "valueCodeableConcept" => { "text" => "radio" } }] }

      result = described_class.call(with_children([item], parent: parent))
      expect(result).not_to be_valid
      expect(result.issues.map { |i| i[:diagnostics] }.join).to include("jsp-8")
    end

    it "jsp-7: rejects initialExpression together with calculatedExpression" do
      item = {
        "linkId" => "q1", "type" => "string",
        "extension" => [
          { "url" => INITIAL_EXPRESSION, "valueExpression" => { "language" => "text/fhirpath", "expression" => "1" } },
          { "url" => CALCULATED_EXPRESSION, "valueExpression" => { "language" => "text/fhirpath", "expression" => "2" } }
        ]
      }

      result = described_class.call(with_children([item]))
      expect(result).not_to be_valid
      expect(result.issues.map { |i| i[:diagnostics] }.join).to include("jsp-7")
    end

    it "jsp-6: requires itemControl on a choice item" do
      expect(described_class.call(with_children([{ "linkId" => "q1", "type" => "choice" }]))).not_to be_valid

      with_control = { "linkId" => "q1", "type" => "choice",
                       "extension" => [{ "url" => ITEM_CONTROL, "valueCodeableConcept" => { "text" => "radio" } }] }
      expect(described_class.call(with_children([with_control]))).to be_valid
    end

    it "jsp-10: requires maxOccurs on a repeating item" do
      repeating = { "linkId" => "sub", "type" => "group", "repeats" => true }
      expect(described_class.call(with_children([repeating]))).not_to be_valid

      repeating = repeating.merge("extension" => [{ "url" => MAX_OCCURS, "valueInteger" => 3 }])
      expect(described_class.call(with_children([repeating]))).to be_valid
    end

    it "jsp-9: requires enableWhen on every child of a choice item" do
      gate = [{ "question" => "group1", "operator" => "=", "answerString" => "yes" }]
      parent = { "type" => "choice",
                 "extension" => [{ "url" => ITEM_CONTROL, "valueCodeableConcept" => { "text" => "radio" } }] }

      partly_gated = with_children(
        [{ "linkId" => "a", "type" => "group", "enableWhen" => gate }, { "linkId" => "b", "type" => "string" }],
        parent: parent
      )
      result = described_class.call(partly_gated)
      expect(result).not_to be_valid
      expect(result.issues.map { |i| i[:diagnostics] }.join).to include("jsp-9")
    end

    it "jsp-9: forbids enableWhen under a non-choice item" do
      gate = [{ "question" => "group1", "operator" => "=", "answerString" => "yes" }]

      result = described_class.call(with_children([{ "linkId" => "a", "type" => "group", "enableWhen" => gate }]))
      expect(result).not_to be_valid
      expect(result.issues.map { |i| i[:diagnostics] }.join).to include("jsp-9")
    end

    it "jsp-2: requires a child's enableWhen.question to be the parent's linkId" do
      parent = { "type" => "choice",
                 "extension" => [{ "url" => ITEM_CONTROL, "valueCodeableConcept" => { "text" => "radio" } }] }
      child = { "linkId" => "a", "type" => "group",
                "enableWhen" => [{ "question" => "somewhere-else", "operator" => "=", "answerString" => "yes" }] }

      result = described_class.call(with_children([child], parent: parent))
      expect(result).not_to be_valid
      expect(result.issues.map { |i| i[:diagnostics] }.join).to include("jsp-2")
    end
  end

  it "rejects a non-ISO8601 date" do
    expect(described_class.call(base_payload("date" => "not-a-date"))).not_to be_valid
  end
end
