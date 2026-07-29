require "net/http"
require "uri"
require "json"
require "zlib"
require "rubygems/package"
require "stringio"
require "fileutils"

# Shared implementation behind the `<ig>:vendor` rake tasks (jp_core, jaspehr).
#
# Downloads an official FHIR Implementation Guide NPM package and extracts just
# the StructureDefinitions/ValueSets/CodeSystems that Fhir::Profile::Validator
# needs, trimmed to the keys it reads. This is dev-time-only: the app never
# downloads anything at runtime, it only reads the committed output under
# vendor/<ig>/.
#
# Each IG differs in only four things, all passed to .run:
#   package_url / package_version  what to download and how to label it
#   vendor_root                    where the trimmed output is written
#   follow                         a ->(canonical_url, index_by_url) predicate
#                                  deciding which canonicals belong to this IG
#
# `follow` doubles as the seed selector: the closure starts from every
# Fhir::ResourceRegistry profile the predicate accepts. The two IGs answer it
# differently on purpose --
#   JP Core  matches on the jpfhir.jp/fhir/core/ canonical prefix, because its
#            package also ships definitions this engine must not vendor.
#   JASPEHR  matches on "the package defines this canonical itself", because it
#            bundles its whole closure (SDC + JP eCS extensions, its own
#            ValueSets/CodeSystems) under four unrelated canonical namespaces.
module IgVendor
  module_function

  def run(package_url:, package_version:, vendor_root:, follow:)
    puts "Downloading #{package_url} ..."
    package_files = extract_package(download(package_url))
    puts "Extracted #{package_files.size} candidate definition file(s) from the package"

    index_by_url = build_url_index(package_files)
    closure = compute_closure(index_by_url, follow)
    puts "Resolved closure: #{closure[:structure_definitions].size} StructureDefinition(s), " \
         "#{closure[:value_sets].size} ValueSet(s), #{closure[:code_systems].size} CodeSystem(s)"

    write_vendor(closure, vendor_root: vendor_root, package_version: package_version, package_url: package_url)
    puts "Wrote #{vendor_root}"
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
      next unless name.match?(%r{\A(StructureDefinition|ValueSet|CodeSystem)-[^/]+\.json\z})

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

  def registry_seed_profiles(index_by_url, follow)
    Fhir::ResourceRegistry::ENTRIES.values
                                   .map { |entry| entry[:profile] }
                                   .compact
                                   .select { |url| follow.call(url, index_by_url) }
                                   .uniq
  end

  def strip_version(canonical_url)
    canonical_url.split("|").first
  end

  # Walks snapshot elements of every profile reachable from the registry,
  # following `type[].profile[]` (datatype/extension profiles) and
  # `binding.valueSet` (required bindings only). Only canonicals the `follow`
  # predicate accepts are pursued -- base HL7 definitions are never vendored,
  # because a resource's snapshot already has all inherited base elements
  # expanded inline. `type[].targetProfile` (Reference targets) is
  # intentionally NOT followed: reference validation stays structural-only
  # (existing FieldExtractor/ResourceValidator behavior), matching the
  # documented scope of this engine.
  def compute_closure(index_by_url, follow)
    structure_definitions = {}
    value_set_queue = []

    sd_queue = registry_seed_profiles(index_by_url, follow)
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
            sd_queue << canonical if follow.call(canonical, index_by_url)
          end
        end

        binding = element["binding"]
        next unless binding && binding["strength"] == "required" && binding["valueSet"]

        value_set_queue << strip_version(binding["valueSet"])
      end
    end

    value_sets, code_systems = resolve_value_sets(value_set_queue, index_by_url, follow)
    { structure_definitions: structure_definitions, value_sets: value_sets, code_systems: code_systems }
  end

  def resolve_value_sets(queue, index_by_url, follow)
    value_sets = {}
    code_systems = {}
    queue = queue.uniq

    until queue.empty?
      url = queue.shift
      next if value_sets.key?(url)
      next unless follow.call(url, index_by_url)

      definition = index_by_url[url]
      unless definition
        warn "WARNING: ValueSet not found in package: #{url}"
        next
      end
      value_sets[url] = definition

      compose_entries(definition).each do |entry|
        if entry["system"]
          cs_url = strip_version(entry["system"])
          if follow.call(cs_url, index_by_url) && !code_systems.key?(cs_url)
            cs_definition = index_by_url[cs_url]
            if cs_definition
              code_systems[cs_url] = cs_definition
            else
              warn "WARNING: CodeSystem not found in package: #{cs_url}"
            end
          end
        end
        Array(entry["valueSet"]).each { |nested| queue << strip_version(nested) }
      end
    end

    [value_sets, code_systems]
  end

  # include and exclude alike: an excluded system/nested ValueSet still has to
  # be vendored, otherwise DefinitionStore cannot subtract it from the expansion.
  def compose_entries(definition)
    Array(definition.dig("compose", "include")) + Array(definition.dig("compose", "exclude"))
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
    trimmed = { "url" => definition["url"], "compose" => { "include" => strip_compose(definition, "include") } }
    exclude = strip_compose(definition, "exclude")
    trimmed["compose"]["exclude"] = exclude if exclude.any?
    trimmed
  end

  def strip_compose(definition, key)
    Array(definition.dig("compose", key)).map do |entry|
      trimmed = {}
      trimmed["system"] = entry["system"] if entry["system"]
      trimmed["valueSet"] = entry["valueSet"] if entry["valueSet"]
      trimmed["concept"] = Array(entry["concept"]).map { |c| { "code" => c["code"] } } if entry["concept"]
      # A `filter` is never evaluated, but its presence must survive trimming:
      # DefinitionStore treats a filtered include as "expansion unknown".
      trimmed["filter"] = entry["filter"] if entry["filter"]
      trimmed
    end
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

  def write_definitions(definitions, dir, kind, vendor_root, &stripper)
    index = {}
    seen_slugs = {}
    FileUtils.mkdir_p(vendor_root.join(dir))

    definitions.each do |url, definition|
      slug = slugify(url)
      raise "Slug collision while vendoring #{kind}: #{slug.inspect} (#{url} vs #{seen_slugs[slug]})" if seen_slugs[slug]

      seen_slugs[slug] = url
      relative_path = "#{dir}/#{slug}.json"
      File.write(vendor_root.join(relative_path), JSON.pretty_generate(stripper.call(definition)))
      index[url] = relative_path
    end

    index
  end

  def write_vendor(closure, vendor_root:, package_version:, package_url:)
    FileUtils.rm_rf(vendor_root)
    FileUtils.mkdir_p(vendor_root)

    index = {
      "structure_definitions" => write_definitions(closure[:structure_definitions], "structure_definitions",
                                                   "StructureDefinition", vendor_root,
                                                   &method(:strip_structure_definition)),
      "value_sets" => write_definitions(closure[:value_sets], "value_sets", "ValueSet", vendor_root,
                                        &method(:strip_value_set)),
      "code_systems" => write_definitions(closure[:code_systems], "code_systems", "CodeSystem", vendor_root,
                                          &method(:strip_code_system)),
      "_meta" => { "package_version" => package_version, "source" => package_url }
    }

    File.write(vendor_root.join("index.json"), JSON.pretty_generate(index))
  end
end
