require_relative "support/ig_vendor"

# Downloads the JASPEHR (the JApanese Standard Platform for EHRs) Implementation
# Guide package and vendors the profile definitions Fhir::Profile::Validator
# needs into vendor/jaspehr/. Covers the Questionnaire / QuestionnaireResponse
# profiles registered in Fhir::ResourceRegistry. See IgVendor for the shared
# mechanics.
namespace :jaspehr do
  desc "Download the JASPEHR IG package and vendor the profile definitions needed for validation into vendor/jaspehr/"
  task vendor: :environment do
    # Unlike jpfhir.jp, jaspehr.jp publishes each build under an unguessable
    # WordPress upload path (.../full-ig_v1.0.0/site/package.tgz), so the URL --
    # not the version -- is the primary knob. JASPEHR_PACKAGE_VERSION only
    # relabels index.json's _meta; set both when moving to a new release.
    version = ENV.fetch("JASPEHR_PACKAGE_VERSION", "1.0.0")
    default_url = "https://jaspehr.jp/wp-content/docs/full-ig_v#{version}/site/package.tgz"

    IgVendor.run(
      package_url: ENV.fetch("JASPEHR_PACKAGE_URL", default_url),
      package_version: version,
      vendor_root: Rails.root.join("vendor", "jaspehr"),
      # The package is self-contained: it bundles its own ValueSets/CodeSystems
      # plus the SDC (hl7.org/fhir/uv/sdc) and JP-CLINS eCS (jpfhir.jp/fhir/clins)
      # extension definitions its profiles reference. Four unrelated canonical
      # namespaces, so "does the package define it" is both simpler and more
      # robust than enumerating prefixes. Everything else (HL7 R4 base types and
      # ValueSets) stays unvendored and is skipped at validation time.
      follow: ->(url, index_by_url) { index_by_url.key?(url) }
    )
  end
end
