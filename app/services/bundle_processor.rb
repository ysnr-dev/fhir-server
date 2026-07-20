class BundleProcessor
  VALID_TYPES = %w[transaction batch].freeze
  # Transactions apply mutations in a fixed order regardless of entry order,
  # so references created earlier in the request are resolvable later.
  PROCESSING_ORDER = %w[DELETE POST PUT PATCH GET].freeze

  Response = Struct.new(:status, :body, keyword_init: true)

  def self.call(bundle, base_url:)
    new(bundle, base_url).call
  end

  def initialize(bundle, base_url)
    @bundle = bundle
    @base_url = base_url
  end

  def call
    return type_error unless VALID_TYPES.include?(bundle["type"])
    return entries_error if Array(bundle["entry"]).empty?

    bundle["type"] == "batch" ? process_batch : process_transaction
  end

  private

  attr_reader :bundle, :base_url

  def type_error
    Response.new(
      status: :unprocessable_entity,
      body: Fhir::OperationOutcome.single(
        severity: "error",
        code: "value",
        diagnostics: "Bundle.type must be 'transaction' or 'batch', got #{bundle['type'].inspect}"
      )
    )
  end

  def entries_error
    Response.new(
      status: :unprocessable_entity,
      body: Fhir::OperationOutcome.single(
        severity: "error",
        code: "required",
        diagnostics: "Bundle.entry is required and must be a non-empty array"
      )
    )
  end

  # Each entry is processed independently; failures don't affect other entries.
  def process_batch
    entries = bundle["entry"]
    response_entries = entries.map { |entry| build_response_entry(entry, dispatch_entry(entry)) }

    Response.new(
      status: :ok,
      body: { "resourceType" => "Bundle", "type" => "batch-response", "entry" => response_entries }
    )
  end

  # All-or-nothing: pre-assign ids for POST entries so same-bundle urn:uuid
  # references resolve, apply in FHIR processing order inside one DB
  # transaction, and roll back entirely if any entry fails.
  def process_transaction
    entries = bundle["entry"]
    pre_assigned_ids = assign_ids(entries)
    reference_map = build_reference_map(entries, pre_assigned_ids)
    resolved_resources = entries.map { |entry| entry["resource"] ? resolve_references(entry["resource"], reference_map) : entry["resource"] }

    order = execution_order(entries, resolved_resources, pre_assigned_ids)
    results = Array.new(entries.size)
    failure_index = nil

    ActiveRecord::Base.transaction do
      order.each do |i|
        result = dispatch_entry(entries[i], resource: resolved_resources[i], id_override: pre_assigned_ids[i])
        results[i] = result

        next if result.success?

        failure_index = i
        raise ActiveRecord::Rollback
      end
    end

    return failed_transaction_response(failure_index, results[failure_index]) if failure_index

    response_entries = entries.each_index.map { |i| build_response_entry(entries[i], results[i]) }
    Response.new(
      status: :ok,
      body: { "resourceType" => "Bundle", "type" => "transaction-response", "entry" => response_entries }
    )
  end

  def failed_transaction_response(index, result)
    outcome = (result.outcome || Fhir::OperationOutcome.single(
      severity: "error", code: "processing", diagnostics: "Bundle.entry[#{index}] failed"
    )).deep_dup
    Array(outcome["issue"]).each { |issue| issue["expression"] = ["Bundle.entry[#{index}]"] + Array(issue["expression"]) }

    Response.new(status: result.status, body: outcome)
  end

  def dispatch_entry(entry, resource: entry["resource"], id_override: nil)
    req = entry["request"] || {}
    method = req["method"].to_s.upcase
    resource_type, id, query_string = parse_url(req["url"])

    return entry_error(:bad_request, "structure", "Bundle.entry.request.url is missing or invalid") if resource_type.blank?
    return entry_error(:bad_request, "not-supported", "Unsupported resourceType '#{resource_type}'") unless Fhir::ResourceRegistry.supported?(resource_type)

    case method
    when "POST"
      Fhir::Operation.create(resource_type, resource, id: id_override)
    when "GET"
      if id.present?
        Fhir::Operation.read(resource_type, id)
      else
        Fhir::Operation.search(resource_type, query_string.to_s, base_url: base_url)
      end
    when "PUT"
      return entry_error(:bad_request, "structure", "PUT requires an id in Bundle.entry.request.url") if id.blank?

      Fhir::Operation.update(resource_type, id, resource, if_match: req["ifMatch"])
    when "DELETE"
      return entry_error(:bad_request, "structure", "DELETE requires an id in Bundle.entry.request.url") if id.blank?

      Fhir::Operation.delete(resource_type, id)
    else
      entry_error(:bad_request, "not-supported", "Unsupported Bundle.entry.request.method '#{method}'")
    end
  end

  def entry_error(status, code, diagnostics)
    Fhir::Operation::Result.new(
      status: status,
      outcome: Fhir::OperationOutcome.single(severity: "error", code: code, diagnostics: diagnostics)
    )
  end

  def build_response_entry(entry, result)
    status_code = Rack::Utils::SYMBOL_TO_STATUS_CODE[result.status] || 500
    reason = Rack::Utils::HTTP_STATUS_CODES[status_code]

    response = { "status" => "#{status_code} #{reason}" }
    response["location"] = "#{base_url}/#{result.location_path}" if result.location_path
    response["etag"] = %(W/"#{result.version_id}") if result.version_id
    response["outcome"] = result.outcome if result.outcome

    entry_hash = { "response" => response }
    entry_hash["resource"] = result.resource if result.resource && result.outcome.nil?
    entry_hash
  end

  # Only POST entries need a pre-assigned id: their server-generated id is
  # otherwise unknown until creation, which is too late for other entries
  # in the same transaction to reference it via fullUrl.
  def assign_ids(entries)
    entries.map do |entry|
      next nil unless method_of(entry) == "POST"

      resource_type = extract_resource_type(entry.dig("request", "url"))
      next nil unless Fhir::ResourceRegistry.supported?(resource_type)

      SecureRandom.uuid
    end
  end

  def build_reference_map(entries, pre_assigned_ids)
    map = {}
    entries.each_with_index do |entry, i|
      next unless pre_assigned_ids[i]

      full_url = entry["fullUrl"]
      next if full_url.blank?

      resource_type = extract_resource_type(entry.dig("request", "url"))
      map[full_url] = "#{resource_type}/#{pre_assigned_ids[i]}"
    end
    map
  end

  def resolve_references(node, reference_map)
    case node
    when Hash
      node.each_with_object({}) do |(k, v), acc|
        acc[k] = (k == "reference" && v.is_a?(String) && reference_map.key?(v)) ? reference_map[v] : resolve_references(v, reference_map)
      end
    when Array
      node.map { |item| resolve_references(item, reference_map) }
    else
      node
    end
  end

  # Orders entries by FHIR processing tier (DELETE, POST, PUT, PATCH, GET).
  # Within the POST tier specifically, entries are further topologically
  # sorted by same-bundle urn:uuid dependency: if entry A's resource
  # references entry B's pre-assigned id, B must run before A, regardless
  # of their relative position in the request's entry array. Other tiers
  # don't need this because the tier ordering itself already guarantees
  # anything a PUT/PATCH/GET could reference from this bundle (a POST) has
  # already run.
  def execution_order(entries, resolved_resources, pre_assigned_ids)
    tiers = Hash.new { |h, k| h[k] = [] }
    entries.each_index { |i| tiers[PROCESSING_ORDER.index(method_of(entries[i])) || PROCESSING_ORDER.size] << i }

    post_tier = PROCESSING_ORDER.index("POST")

    (0..PROCESSING_ORDER.size).flat_map do |tier|
      indices = tiers[tier]
      tier == post_tier ? topological_sort(indices, entries, resolved_resources, pre_assigned_ids) : indices
    end
  end

  def topological_sort(indices, entries, resolved_resources, pre_assigned_ids)
    created_reference = indices.index_with do |i|
      "#{extract_resource_type(entries[i].dig('request', 'url'))}/#{pre_assigned_ids[i]}"
    end

    remaining = indices.dup
    sorted = []

    until remaining.empty?
      ready, blocked = remaining.partition do |i|
        (remaining - [i]).none? { |j| references?(resolved_resources[i], created_reference[j]) }
      end

      # A dependency cycle would leave `ready` empty; fall back to remaining
      # array order rather than looping forever.
      if ready.empty?
        sorted.concat(remaining)
        break
      end

      sorted.concat(ready)
      remaining = blocked
    end

    sorted
  end

  def references?(resource, literal)
    case resource
    when Hash
      resource.any? { |k, v| (k == "reference" && v == literal) || references?(v, literal) }
    when Array
      resource.any? { |item| references?(item, literal) }
    else
      false
    end
  end

  def method_of(entry)
    entry.dig("request", "method").to_s.upcase
  end

  def extract_resource_type(url)
    url.to_s.split("?").first.to_s.split("/").first
  end

  def parse_url(url)
    path, query_string = url.to_s.split("?", 2)
    segments = path.split("/")
    [segments[0], segments[1], query_string]
  end
end
