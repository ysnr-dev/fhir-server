require_relative "support/ig_vendor"

# Downloads the official JP Core Implementation Guide package and vendors the
# profile definitions Fhir::Profile::Validator needs into vendor/jp_core/.
# Re-run this whenever the JP Core package version changes or
# Fhir::ResourceRegistry gains/loses a JP Core profile. See IgVendor for the
# shared mechanics (and lib/tasks/jaspehr.rake for the second IG).
namespace :jp_core do
  desc "Download the JP Core package and vendor the profile definitions needed for validation into vendor/jp_core/"
  task vendor: :environment do
    # A version bump normally needs only JP_CORE_PACKAGE_VERSION (e.g.
    # `JP_CORE_PACKAGE_VERSION=1.3.0 bin/rails jp_core:vendor`), since jpfhir.jp
    # publishes each release at .../core/<version>/package.tgz. JP_CORE_PACKAGE_URL
    # is an escape hatch for anything that doesn't follow that pattern (a
    # pre-release build, a local mirror for offline testing, ...); when set, it
    # wins outright and the version becomes purely the label recorded in
    # index.json's _meta -- it does not need to match the URL's own path.
    version = ENV.fetch("JP_CORE_PACKAGE_VERSION", "1.2.0")

    # Changes only if the JP Core canonical namespace itself ever changes.
    jp_core_prefix = "http://jpfhir.jp/fhir/core/"

    IgVendor.run(
      package_url: ENV.fetch("JP_CORE_PACKAGE_URL", "https://jpfhir.jp/fhir/core/#{version}/package.tgz"),
      package_version: version,
      vendor_root: Rails.root.join("vendor", "jp_core"),
      # The JP Core package also ships definitions outside its own canonical
      # namespace, so membership is decided by prefix rather than by "is it in
      # the package" (contrast jaspehr.rake).
      follow: ->(url, _index_by_url) { url.to_s.start_with?(jp_core_prefix) }
    )
  end
end
