require "rails_helper"

# Guards the declarative extraction contract for EVERY registered resource, so a new
# resource added with a typo'd column (or a definition drifting from the schema) fails
# loudly here rather than at persist time.
RSpec.describe "Fhir::ExtractionDefinitions integrity" do
  TOKEN_KINDS = %i[code code_list codeable_concept codeable_concept_list coding coding_list identifier].freeze

  Fhir::ResourceRegistry.types.each do |resource_type|
    entry = Fhir::ResourceRegistry.entry_for(resource_type)
    model = entry.fetch(:model)
    extraction = entry.fetch(:extraction)
    token_extraction = entry.fetch(:token_extraction)
    token_params = entry.fetch(:search_params).select { |_n, d| %i[token token_or_text].include?(d[:type]) }.keys

    describe resource_type do
      it "declares an extraction map" do
        expect(extraction).to be_a(Hash)
        expect(extraction).not_to be_empty
      end

      it "targets only real columns on #{resource_type}'s table" do
        unknown = extraction.keys.map(&:to_s) - model.column_names
        expect(unknown).to be_empty, "extraction targets missing columns: #{unknown.join(', ')}"
      end

      it "uses only transforms implemented by Fhir::FieldExtractor" do
        transforms = extraction.values.filter_map { |spec| spec[:transform] }
        missing = transforms.reject { |t| Fhir::FieldExtractor.respond_to?(t) }
        expect(missing).to be_empty, "unknown transforms: #{missing.join(', ')}"
      end

      it "gives every spec a path" do
        pathless = extraction.select { |_col, spec| spec[:path].blank? }.keys
        expect(pathless).to be_empty, "specs missing :path: #{pathless.join(', ')}"
      end

      it "declares a token spec for exactly its token / token_or_text search params" do
        expect(token_extraction.keys).to match_array(token_params)
      end

      it "uses only known token kinds and non-blank paths" do
        token_extraction.each do |param, spec|
          expect(TOKEN_KINDS).to include(spec[:kind]), "#{param}: bad kind #{spec[:kind].inspect}"
          expect(spec[:path]).to be_present, "#{param}: missing path"
        end
      end
    end
  end

  it "runs sync_search_fields! for every resource type without raising on empty content" do
    Fhir::ResourceRegistry.types.each do |resource_type|
      model = Fhir::ResourceRegistry.entry_for(resource_type).fetch(:model)
      record = model.new(id: SecureRandom.uuid, version_id: 1, content: {}, last_updated: Time.current)
      expect { record.sync_search_fields! }.not_to raise_error
    end
  end

  it "extracts no token rows from empty content for every resource type" do
    Fhir::ResourceRegistry.types.each do |resource_type|
      tokens = Fhir::ResourceRegistry.entry_for(resource_type).fetch(:token_extraction)
      expect(Fhir::TokenExtractor.rows({}, tokens)).to eq([])
    end
  end
end
