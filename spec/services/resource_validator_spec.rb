require "rails_helper"

RSpec.describe ResourceValidator do
  # A stub subclass named to look like a real resource validator, so
  # `resource_type` derivation ("Patient") can be exercised.
  before do
    stub_const("PatientValidator", Class.new(described_class) do
      def validate
        @plan.each { |step| instance_exec(&step) }
      end

      def plan(&block)
        (@plan ||= []) << block
      end
    end)
  end

  def validator_running(&block)
    klass = PatientValidator
    instance = klass.new(payload)
    instance.instance_variable_set(:@plan, [block])
    instance.call
  end

  let(:payload) { {} }

  describe "contract" do
    it "returns a Result responding to valid?/issues via .call" do
      stub_const("PatientValidator", Class.new(described_class) do
        def validate; end
      end)

      result = PatientValidator.call({})
      expect(result).to be_valid
      expect(result.issues).to eq([])
    end
  end

  describe "#resource_type" do
    it "derives the FHIR type from the class name" do
      result = validator_running { add_error(code: "x", diagnostics: "d", expression: "#{resource_type}.foo") }
      expect(result.issues.first[:expression]).to eq(["Patient.foo"])
    end
  end

  describe "#add_error / #add_warning" do
    it "separates errors (invalid) from warnings (valid) and attaches severity" do
      result = validator_running do
        add_error(code: "value", diagnostics: "bad", expression: "Patient.a")
        add_warning(code: "value", diagnostics: "meh", expression: "Patient.b")
      end

      expect(result).not_to be_valid
      expect(result.issues).to contain_exactly(
        { code: "value", diagnostics: "bad", expression: ["Patient.a"], severity: "error" },
        { code: "value", diagnostics: "meh", expression: ["Patient.b"], severity: "warning" }
      )
    end

    it "wraps a scalar expression into an array" do
      result = validator_running { add_error(code: "x", diagnostics: "d", expression: "Patient.a") }
      expect(result.issues.first[:expression]).to eq(["Patient.a"])
    end
  end

  describe "#require_field" do
    let(:payload) { { "active" => false } }

    it "treats false as present (for boolean elements)" do
      result = validator_running { require_field("active") }
      expect(result).to be_valid
    end

    it "flags a blank field and returns false" do
      returned = nil
      result = validator_running { returned = require_field("status") }
      expect(result.issues.first).to include(code: "required", expression: ["Patient.status"])
      expect(returned).to be(false)
    end

    it "appends a cardinality note when given" do
      result = validator_running { require_field("identifier", cardinality: "1..*") }
      expect(result.issues.first[:diagnostics]).to eq("Patient.identifier is required (JP Core: 1..*)")
    end
  end

  describe "#validate_binding" do
    it "accepts a bound value and ignores an absent one" do
      expect(validator_running { validate_binding("gender", %w[male female]) }).to be_valid
    end

    context "with an out-of-binding value" do
      let(:payload) { { "gender" => "wrong" } }

      it "emits a value error listing the allowed codes" do
        result = validator_running { validate_binding("gender", %w[male female]) }
        expect(result.issues.first).to include(code: "value", expression: ["Patient.gender"])
        expect(result.issues.first[:diagnostics]).to include("male, female")
      end
    end
  end

  describe "#validate_date" do
    it "accepts partial and full dates" do
      expect(described_class.new({}).send(:pad_partial_date, "2024")).to eq("2024-01-01")
      expect(validator_with("birthDate" => "2024").call).to be_valid
      expect(validator_with("birthDate" => "2024-05").call).to be_valid
      expect(validator_with("birthDate" => "2024-05-06").call).to be_valid
    end

    it "rejects a malformed date" do
      expect(validator_with("birthDate" => "not-a-date").call).not_to be_valid
    end

    it "rejects an impossible calendar date" do
      expect(validator_with("birthDate" => "2024-02-31").call).not_to be_valid
    end

    def validator_with(payload)
      instance = PatientValidator.new(payload)
      instance.instance_variable_set(:@plan, [-> { validate_date("birthDate") }])
      instance
    end
  end

  describe "#validate_boolean" do
    it "accepts true/false and an absent key" do
      expect(bool_validator({}).call).to be_valid
      expect(bool_validator("active" => true).call).to be_valid
      expect(bool_validator("active" => false).call).to be_valid
    end

    it "rejects a non-boolean" do
      expect(bool_validator("active" => "yes").call).not_to be_valid
    end

    def bool_validator(payload)
      instance = PatientValidator.new(payload)
      instance.instance_variable_set(:@plan, [-> { validate_boolean("active") }])
      instance
    end
  end

  describe "#validate_patient_reference" do
    def ref_validator(payload, on_non_patient:)
      instance = PatientValidator.new(payload)
      instance.instance_variable_set(:@plan, [-> { validate_patient_reference("subject", on_non_patient: on_non_patient) }])
      instance
    end

    it "accepts an existing, non-deleted Patient reference" do
      patient = Fhir::Repository.create("Patient", { "resourceType" => "Patient", "identifier" => [{ "value" => "ref-1" }] })
      result = ref_validator({ "subject" => { "reference" => "Patient/#{patient.id}" } }, on_non_patient: :reject).call
      expect(result).to be_valid
    end

    it "rejects a non-existent Patient reference" do
      result = ref_validator({ "subject" => { "reference" => "Patient/missing" } }, on_non_patient: :reject).call
      expect(result.issues.first).to include(code: "invalid")
    end

    it "rejects a non-Patient reference when on_non_patient: :reject" do
      result = ref_validator({ "subject" => { "reference" => "Group/g1" } }, on_non_patient: :reject).call
      expect(result.issues.first).to include(code: "value")
    end

    it "accepts a non-Patient reference when on_non_patient: :skip" do
      result = ref_validator({ "subject" => { "reference" => "Location/l1" } }, on_non_patient: :skip).call
      expect(result).to be_valid
    end
  end
end
