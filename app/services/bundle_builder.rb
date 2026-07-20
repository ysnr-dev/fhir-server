class BundleBuilder
  def self.searchset(result:, base_url:, query_params:, resource_type:, included: [])
    new(base_url, resource_type).searchset(result: result, query_params: query_params, included: included)
  end

  def self.history(resource_id:, versions:, base_url:, resource_type:)
    new(base_url, resource_type).history(resource_id: resource_id, versions: versions)
  end

  def initialize(base_url, resource_type)
    @base_url = base_url
    @resource_type = resource_type
  end

  def searchset(result:, query_params:, included: [])
    entries = result.records.map do |record|
      {
        "fullUrl" => "#{base_url}/#{resource_type}/#{record.id}",
        "resource" => Fhir::Meta.apply(record.content, version_id: record.version_id, last_updated: record.last_updated),
        "search" => { "mode" => "match" }
      }
    end

    entries.concat(include_entries(included, seen_urls: entries.map { |entry| entry["fullUrl"] }))

    {
      "resourceType" => "Bundle",
      "type" => "searchset",
      "total" => result.total,
      "link" => search_links(result: result, query_params: query_params),
      "entry" => entries
    }
  end

  def history(resource_id:, versions:)
    entries = versions.reverse_each.map do |version|
      entry = {
        "fullUrl" => "#{base_url}/#{resource_type}/#{resource_id}",
        "request" => {
          "method" => version.version_id == 1 ? "POST" : (version.deleted ? "DELETE" : "PUT"),
          "url" => "#{resource_type}/#{resource_id}"
        },
        "response" => {
          "status" => version.deleted ? "410" : "200",
          "etag" => %(W/"#{version.version_id}"),
          "lastModified" => version.last_updated.utc.iso8601(3)
        }
      }
      entry["resource"] = Fhir::Meta.apply(version.content, version_id: version.version_id, last_updated: version.last_updated) unless version.deleted
      entry
    end

    {
      "resourceType" => "Bundle",
      "type" => "history",
      "total" => versions.size,
      "entry" => entries
    }
  end

  private

  attr_reader :base_url, :resource_type

  # Renders `_include`/`_revinclude` resources as `search.mode = "include"`
  # entries, skipping any whose fullUrl already appears (as a match or an earlier
  # include). Each included record may be a different resourceType than the
  # searched one, so the type is read from its own `content`.
  def include_entries(included, seen_urls:)
    seen = seen_urls.to_set

    included.filter_map do |record|
      type = record.content["resourceType"]
      full_url = "#{base_url}/#{type}/#{record.id}"
      next if seen.include?(full_url)

      seen << full_url
      {
        "fullUrl" => full_url,
        "resource" => Fhir::Meta.apply(record.content, version_id: record.version_id, last_updated: record.last_updated),
        "search" => { "mode" => "include" }
      }
    end
  end

  def search_links(result:, query_params:)
    links = [{ "relation" => "self", "url" => page_url(query_params, result.offset) }]

    if result.offset.positive?
      previous_offset = [result.offset - result.count, 0].max
      links << { "relation" => "previous", "url" => page_url(query_params, previous_offset) }
    end

    if result.offset + result.count < result.total
      links << { "relation" => "next", "url" => page_url(query_params, result.offset + result.count) }
    end

    links
  end

  def page_url(query_params, offset)
    params = query_params.except("_offset").merge("_offset" => offset)
    query_string = params.to_query
    "#{base_url}/#{resource_type}?#{query_string}"
  end
end
