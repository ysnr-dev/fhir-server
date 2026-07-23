require "net/http"
require "uri"
require "json"
require "zlib"
require "rubygems/package"
require "stringio"
require "fileutils"

# Downloads the official JP Core Implementation Guide package and extracts
# just the StructureDefinitions/ValueSets/CodeSystems that
# Fhir::Profile::Validator needs, trimmed to the keys it reads. This is a
# dev-time-only task: the app never downloads anything at runtime, it only
# reads the committed output under vendor/jp_core/. Re-run this whenever the
# JP Core package version changes or Fhir::ResourceRegistry gains/loses a
# JP Core profile.
namespace :jp_core do
  desc "Download the JP Core package and vendor the profile definitions needed for validation into vendor/jp_core/"
  task vendor: :environment do
    JpCoreVendor.run
  end
end

module JpCoreVendor
  PACKAGE_URL = ENV.fetch("JP_CORE_PACKAGE_URL", "https://jpfhir.jp/fhir/core/1.2.0/package.tgz")
  PACKAGE_VERSION = "1.2.0".freeze
  # Not a reference to Fhir::Profile::JP_CORE_PREFIX: .rake files load before
  # the app's autoloader can resolve app/lib constants, so this stays a
  # separate literal (kept in sync by inspection -- it changes only if the
  # JP Core canonical namespace itself ever changes).
  JP_CORE_PREFIX = "http://jpfhir.jp/fhir/core/".freeze
  VENDOR_ROOT = Rails.root.join("vendor", "jp_core")

  module_function

  def run
    puts "Downloading #{PACKAGE_URL} ..."
    package_files = extract_package(download(PACKAGE_URL))
    puts "Extracted #{package_files.size} candidate definition file(s) from the package"

    index_by_url = build_url_index(package_files)
    closure = compute_closure(index_by_url)
    puts "Resolved closure: #{closure[:structure_definitions].size} StructureDefinition(s), " \
         "#{closure[:value_sets].size} ValueSet(s), #{closure[:code_systems].size} CodeSystem(s)"

    write_vendor(closure)
    puts "Wrote #{VENDOR_ROOT}"
  end

  # --- download & extract ---------------------------------------------------

  def download(url, redirects_left: 5)
    raise "Too many redirects while downloading #{url}" if redirects_left.negative?

    response = Net::HTTP.get_response(URI.parse(url))
    case response
    when Net::HTTPRedirection
      download(response["location"], redirects_left: redirects_left - 1)
    when Net::HTTPSuccess
      response.body
    else
      raise "Failed to download #{url}: #{response.code} #{response.message}"
    end
  end

  # Returns { "StructureDefinition-jp-patient.json" => parsed_hash, ... } for
  # every StructureDefinition/ValueSet/CodeSystem at the top level of the
  # package (the "example/", "xml/", "openapi/" subdirectories are skipped).
  def extract_package(tgz_bytes)
    files = {}
    tar = Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(tgz_bytes)))
    tar.each do |entry|
      next unless entry.file?

      name = entry.full_name.sub(%r{\Apackage/}, "")
      next unless name.match?(/\A(StructureDefinition|ValueSet|CodeSystem)-[^\/]+\.json\z/)

      files[name] = JSON.parse(entry.read.force_encoding("UTF-8"))
    end
    tar.close
    files
  end

  def build_url_index(files)
    index = {}
    files.each_value do |definition|
      url = definition["url"]
      index[url] = definition if url
    end
    index
  end

  # --- transitive closure ----------------------------------------------------

  def jp_core_registry_profiles
    Fhir::ResourceRegistry::ENTRIES.values
                                    .map { |entry| entry[:profile] }
                                    .select { |url| url.start_with?(JP_CORE_PREFIX) }
                                    .uniq
  end

  def strip_version(canonical_url)
    canonical_url.split("|").first
  end

  # Walks snapshot elements of every JP Core profile reachable from the
  # registry, following `type[].profile[]` (datatype/extension profiles) and
  # `binding.valueSet` (required bindings only). Only jpfhir.jp canonicals are
  # followed -- base HL7 definitions are never vendored, because a resource's
  # snapshot already has all inherited base elements expanded inline.
  # `type[].targetProfile` (Reference targets) is intentionally NOT followed:
  # reference validation stays structural-only (existing FieldExtractor/
  # ResourceValidator behavior), matching the documented scope of this engine.
  def compute_closure(index_by_url)
    structure_definitions = {}
    value_set_queue = []

    sd_queue = jp_core_registry_profiles.dup
    until sd_queue.empty?
      url = sd_queue.shift
      next if structure_definitions.key?(url)

      definition = index_by_url[url]
      unless definition
        warn "WARNING: StructureDefinition not found in package: #{url}"
        next
      end
      structure_definitions[url] = definition

      Array(definition.dig("snapshot", "element")).each do |element|
        Array(element["type"]).each do |type|
          Array(type["profile"]).each do |profile_url|
            canonical = strip_version(profile_url)
            sd_queue << canonical if canonical.start_with?(JP_CORE_PREFIX)
          end
        end

        binding = element["binding"]
        next unless binding && binding["strength"] == "required" && binding["valueSet"]

        value_set_queue << strip_version(binding["valueSet"])
      end
    end

    value_sets, code_systems = resolve_value_sets(value_set_queue, index_by_url)
    { structure_definitions: structure_definitions, value_sets: value_sets, code_systems: code_systems }
  end

  def resolve_value_sets(queue, index_by_url)
    value_sets = {}
    code_systems = {}
    queue = queue.uniq

    until queue.empty?
      url = queue.shift
      next if value_sets.key?(url)
      next unless url.start_with?(JP_CORE_PREFIX)

      definition = index_by_url[url]
      unless definition
        warn "WARNING: ValueSet not found in package: #{url}"
        next
      end
      value_sets[url] = definition

      Array(definition.dig("compose", "include")).each do |include_entry|
        if include_entry["system"]
          cs_url = strip_version(include_entry["system"])
          if cs_url.start_with?(JP_CORE_PREFIX) && !code_systems.key?(cs_url)
            cs_definition = index_by_url[cs_url]
            if cs_definition
              code_systems[cs_url] = cs_definition
            else
              warn "WARNING: CodeSystem not found in package: #{cs_url}"
            end
          end
        end
        Array(include_entry["valueSet"]).each { |nested| queue << strip_version(nested) }
      end
    end

    [value_sets, code_systems]
  end

  # --- trimming ---------------------------------------------------------------

  def strip_structure_definition(definition)
    {
      "url" => definition["url"],
      "type" => definition["type"],
      "snapshot" => { "element" => Array(definition.dig("snapshot", "element")).map { |e| strip_element(e) } }
    }
  end

  def strip_element(element)
    # `id` (not just `path`) is required: it's the only field that carries
    # slice scoping in dotted form (e.g. "MedicationRequest.identifier:
    # rpNumber.system" vs plain path "MedicationRequest.identifier.system"),
    # which ElementTree needs to scope a slice's children correctly.
    trimmed = { "id" => element["id"], "path" => element["path"] }
    trimmed["sliceName"] = element["sliceName"] if element["sliceName"]
    trimmed["slicing"] = element["slicing"] if element["slicing"]
    trimmed["min"] = element["min"] if element.key?("min")
    trimmed["max"] = element["max"] if element.key?("max")
    trimmed["base"] = element["base"].slice("path", "min", "max") if element["base"]
    trimmed["type"] = element["type"].map { |t| t.slice("code", "profile") } if element["type"]
    trimmed["binding"] = element["binding"].slice("strength", "valueSet") if element["binding"]
    trimmed["contentReference"] = element["contentReference"] if element["contentReference"]
    element.each do |key, value|
      trimmed[key] = value if key.start_with?("fixed") || key.start_with?("pattern")
    end
    trimmed
  end

  def strip_value_set(definition)
    include_entries = Array(definition.dig("compose", "include")).map do |inc|
      entry = {}
      entry["system"] = inc["system"] if inc["system"]
      entry["valueSet"] = inc["valueSet"] if inc["valueSet"]
      entry["concept"] = Array(inc["concept"]).map { |c| { "code" => c["code"] } } if inc["concept"]
      entry
    end
    { "url" => definition["url"], "compose" => { "include" => include_entries } }
  end

  def strip_code_system(definition)
    { "url" => definition["url"], "concept" => strip_concepts(definition["concept"]) }
  end

  def strip_concepts(concepts)
    Array(concepts).map do |c|
      entry = { "code" => c["code"] }
      entry["concept"] = strip_concepts(c["concept"]) if c["concept"]
      entry
    end
  end

  # --- write ------------------------------------------------------------------

  def slugify(url)
    url.split("/").last.gsub(/[^A-Za-z0-9_.-]/, "_")
  end

  def write_definitions(definitions, dir, kind, &stripper)
    index = {}
    seen_slugs = {}
    FileUtils.mkdir_p(VENDOR_ROOT.join(dir))

    definitions.each do |url, definition|
      slug = slugify(url)
      raise "Slug collision while vendoring #{kind}: #{slug.inspect} (#{url} vs #{seen_slugs[slug]})" if seen_slugs[slug]

      seen_slugs[slug] = url
      relative_path = "#{dir}/#{slug}.json"
      File.write(VENDOR_ROOT.join(relative_path), JSON.pretty_generate(stripper.call(definition)))
      index[url] = relative_path
    end

    index
  end

  def write_vendor(closure)
    FileUtils.rm_rf(VENDOR_ROOT)
    FileUtils.mkdir_p(VENDOR_ROOT)

    index = {
      "structure_definitions" => write_definitions(closure[:structure_definitions], "structure_definitions",
                                                     "StructureDefinition", &method(:strip_structure_definition)),
      "value_sets" => write_definitions(closure[:value_sets], "value_sets", "ValueSet", &method(:strip_value_set)),
      "code_systems" => write_definitions(closure[:code_systems], "code_systems", "CodeSystem",
                                           &method(:strip_code_system)),
      "_meta" => { "package_version" => PACKAGE_VERSION, "source" => PACKAGE_URL }
    }

    File.write(VENDOR_ROOT.join("index.json"), JSON.pretty_generate(index))
  end
end
