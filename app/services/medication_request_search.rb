class MedicationRequestSearch
  DEFAULT_COUNT = 20
  MAX_COUNT = 100
  DATE_PREFIX_PATTERN = /\A(eq|ge|le|gt|lt)(.+)\z/.freeze

  Result = Struct.new(:records, :total, :count, :offset, keyword_init: true)

  def self.call(params)
    new(params).call
  end

  def initialize(params)
    @params = params
  end

  def call
    scope = MedicationRequest.where(deleted: false)
    scope = filter_id(scope)
    scope = filter_identifier(scope)
    scope = filter_status(scope)
    scope = filter_intent(scope)
    scope = filter_subject(scope)
    scope = filter_code(scope)
    scope = filter_authoredon(scope)
    scope = filter_last_updated(scope)

    total = scope.count
    count = clamped_count
    offset = clamped_offset
    records = scope.order(:id).limit(count).offset(offset)

    Result.new(records: records, total: total, count: count, offset: offset)
  end

  private

  attr_reader :params

  def filter_id(scope)
    return scope if params["_id"].blank?

    scope.where(id: params["_id"])
  end

  def filter_identifier(scope)
    return scope if params["identifier"].blank?

    value = params["identifier"]
    ids = if value.include?("|")
            system, val = value.split("|", 2)
            MedicationRequestIdentifier.where(system: system, value: val).select(:medication_request_id)
          else
            MedicationRequestIdentifier.where(value: value).select(:medication_request_id)
          end
    scope.where(id: ids)
  end

  def filter_status(scope)
    return scope if params["status"].blank?

    scope.where(status: params["status"])
  end

  def filter_intent(scope)
    return scope if params["intent"].blank?

    scope.where(intent: params["intent"])
  end

  def filter_subject(scope)
    value = params["subject"].presence || params["patient"].presence
    return scope if value.blank?

    reference = value.include?("/") ? value : "Patient/#{value}"
    scope.where(subject_reference: reference)
  end

  def filter_code(scope)
    return scope if params["code"].blank?

    value = params["code"]
    scope.where(medication_code: value).or(scope.where("medication_text ILIKE ?", like_pattern(value)))
  end

  def filter_authoredon(scope)
    return scope if params["authoredon"].blank?

    prefix, date_str = split_prefix(params["authoredon"])
    time = parse_time(date_str)
    return scope unless time

    apply_comparison(scope, "authored_on", prefix, time)
  end

  def filter_last_updated(scope)
    return scope if params["_lastUpdated"].blank?

    prefix, date_str = split_prefix(params["_lastUpdated"])
    time = parse_time(date_str)
    return scope unless time

    apply_comparison(scope, "last_updated", prefix, time)
  end

  def apply_comparison(scope, column, prefix, value)
    case prefix
    when "ge" then scope.where("#{column} >= ?", value)
    when "le" then scope.where("#{column} <= ?", value)
    when "gt" then scope.where("#{column} > ?", value)
    when "lt" then scope.where("#{column} < ?", value)
    else scope.where(column => value)
    end
  end

  def split_prefix(value)
    match = value.match(DATE_PREFIX_PATTERN)
    match ? [match[1], match[2]] : ["eq", value]
  end

  def parse_time(str)
    Time.iso8601(str)
  rescue ArgumentError, TypeError
    nil
  end

  def clamped_count
    count = params["_count"].present? ? params["_count"].to_i : DEFAULT_COUNT
    count = DEFAULT_COUNT if count <= 0
    [count, MAX_COUNT].min
  end

  def clamped_offset
    offset = params["_offset"].present? ? params["_offset"].to_i : 0
    offset.negative? ? 0 : offset
  end

  def like_pattern(str)
    "%#{str.gsub(/[%_\\]/) { |c| "\\#{c}" }}%"
  end
end
