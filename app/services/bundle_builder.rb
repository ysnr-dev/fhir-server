class BundleBuilder
  def self.searchset(result:, base_url:, search_params:, resource_type:, included: [], shaper: nil)
    new(base_url, resource_type).searchset(result: result, search_params: search_params, included: included, shaper: shaper)
  end

  def self.history(resource_id:, versions:, base_url:, resource_type:)
    new(base_url, resource_type).history(resource_id: resource_id, versions: versions)
  end

  # Type-/system-level history: entries span multiple resources (and, for the
  # system level, multiple types), so each entry's type/id comes from its
  # ResourceVersion row rather than from the builder. `path` is the request
  # path the pagination links point back at ("Patient/_history" or "_history").
  def self.history_page(page:, base_url:, path:, params:)
    new(base_url, nil).history_page(page: page, path: path, params: params)
  end

  def initialize(base_url, resource_type)
    @base_url = base_url
    @resource_type = resource_type
  end

  def searchset(result:, search_params:, included: [], shaper: nil)
    bundle = { "resourceType" => "Bundle", "type" => "searchset" }
    # _total=none leaves total nil -> the element is omitted per spec.
    bundle["total"] = result.total unless result.total.nil?
    bundle["link"] = search_links(result: result, search_params: search_params)
    # _summary=count: totals and links only, no entry element at all.
    return bundle if search_params.summary == "count"

    entries = result.records.map do |record|
      {
        "fullUrl" => "#{base_url}/#{resource_type}/#{record.id}",
        "resource" => shaped(record, shaper),
        "search" => { "mode" => "match" }
      }
    end

    entries.concat(include_entries(included, seen_urls: entries.map { |entry| entry["fullUrl"] }, shaper: shaper))

    bundle["entry"] = entries
    bundle
  end

  def history(resource_id:, versions:)
    {
      "resourceType" => "Bundle",
      "type" => "history",
      "total" => versions.size,
      "entry" => versions.reverse_each.map { |version| history_entry(version, resource_type: resource_type, resource_id: resource_id) }
    }
  end

  def history_page(page:, path:, params:)
    {
      "resourceType" => "Bundle",
      "type" => "history",
      "total" => page.total,
      "link" => history_links(page: page, path: path, params: params),
      "entry" => page.versions.map { |version| history_entry(version, resource_type: version.resource_type, resource_id: version.resource_id) }
    }
  end

  private

  attr_reader :base_url, :resource_type

  def history_entry(version, resource_type:, resource_id:)
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

  def history_links(page:, path:, params:)
    page_url = ->(offset) { "#{base_url}/#{path}?#{params.to_query(offset: offset)}" }
    links = [{ "relation" => "self", "url" => page_url.call(page.offset) }]

    if page.offset.positive?
      links << { "relation" => "previous", "url" => page_url.call([page.offset - page.count, 0].max) }
    end

    if page.offset + page.count < page.total
      links << { "relation" => "next", "url" => page_url.call(page.offset + page.count) }
    end

    links
  end

  # Renders `_include`/`_revinclude` resources as `search.mode = "include"`
  # entries, skipping any whose fullUrl already appears (as a match or an earlier
  # include). Each included record may be a different resourceType than the
  # searched one, so the type is read from its own `content`.
  def include_entries(included, seen_urls:, shaper: nil)
    seen = seen_urls.to_set

    included.filter_map do |record|
      type = record.content["resourceType"]
      full_url = "#{base_url}/#{type}/#{record.id}"
      next if seen.include?(full_url)

      seen << full_url
      {
        "fullUrl" => full_url,
        "resource" => shaped(record, shaper),
        "search" => { "mode" => "include" }
      }
    end
  end

  def shaped(record, shaper)
    resource = Fhir::Meta.apply(record.content, version_id: record.version_id, last_updated: record.last_updated)
    shaper ? shaper.call(resource) : resource
  end

  def search_links(result:, search_params:)
    links = [{ "relation" => "self", "url" => page_url(search_params, result.offset) }]

    if result.offset.positive?
      previous_offset = [result.offset - result.count, 0].max
      links << { "relation" => "previous", "url" => page_url(search_params, previous_offset) }
    end

    links << { "relation" => "next", "url" => page_url(search_params, result.offset + result.count) } if next_page?(result)

    links
  end

  # Without a total (_total=none) a full page implies a next page; the standard
  # tradeoff is one possibly-empty final page when the last page is exactly full.
  def next_page?(result)
    return result.offset + result.count < result.total if result.total

    result.records.length == result.count
  end

  def page_url(search_params, offset)
    "#{base_url}/#{resource_type}?#{search_params.to_query(offset: offset)}"
  end
end
