require "rails_helper"

RSpec.describe Fhir::ResourceRegistry do
  # config/routes.rb repeats the registry's type names as literal strings so
  # loading routes never autoloads application code at boot. That duplication is
  # guarded only by a comment, and every new resource type has to update both.
  describe "route coverage" do
    def routed_resource_types
      Rails.application.routes.routes
           .filter_map { |route| route.defaults[:resource_type] }
           .uniq
    end

    it "routes every registered type" do
      expect(described_class.types - routed_resource_types).to be_empty
    end

    it "registers every routed type" do
      expect(routed_resource_types - described_class.types).to be_empty
    end
  end

  describe "entry shape" do
    it "gives every type a model, validator, and profile" do
      described_class::ENTRIES.each do |resource_type, entry|
        expect(entry[:model]).to be < ApplicationRecord, "#{resource_type} has no model"
        expect(entry[:validator]).to be < ResourceValidator, "#{resource_type} has no validator"
        expect(entry[:profile]).to be_present, "#{resource_type} has no profile"
      end
    end

    # FhirResourceRecord relies on Rails' polymorphic `resource_type` column
    # doubling as the FHIR resourceType, so the two must agree even where the
    # Ruby class name differs (Coverage -> InsuranceCoverage).
    it "keeps each model's polymorphic name equal to its FHIR resourceType" do
      described_class::ENTRIES.each do |resource_type, entry|
        expect(entry[:model].polymorphic_name).to eq(resource_type)
      end
    end
  end
end
