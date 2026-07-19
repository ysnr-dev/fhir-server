class OrganizationSearch
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
    scope = Organization.where(deleted: false)
    scope = filter_id(scope)
    scope = filter_identifier(scope)
    scope = filter_name(scope)
    scope = filter_active(scope)
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
            OrganizationIdentifier.where(system: system, value: val).select(:organization_id)
          else
            OrganizationIdentifier.where(value: value).select(:organization_id)
          end
    scope.where(id: ids)
  end

  def filter_name(scope)
    return scope if params["name"].blank?

    scope.where("name ILIKE ?", like_pattern(params["name"]))
  end

  def filter_active(scope)
    return scope if params["active"].blank?

    scope.where(active: ActiveModel::Type::Boolean.new.cast(params["active"]))
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
