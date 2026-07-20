module Fhir
  # Executes a FHIR search against a single resource type, driven by the declarative
  # parameter definitions registered per type (see Fhir::SearchDefinitions::*) instead
  # of a hand-written search class per resource.
  class Search
    DEFAULT_COUNT = 20
    MAX_COUNT = 100
    DATE_PREFIX_PATTERN = /\A(eq|ge|le|gt|lt)(.+)\z/.freeze

    Result = Struct.new(:records, :total, :count, :offset, keyword_init: true)

    def self.call(resource_type, params)
      new(resource_type, params).call
    end

    def initialize(resource_type, params)
      entry = ResourceRegistry.entry_for(resource_type)
      @resource_type = resource_type
      @model = entry.fetch(:model)
      @search_params = entry.fetch(:search_params)
      @params = params
    end

    def call
      scope = model.where(deleted: false)
      scope = filter_id(scope)
      scope = filter_last_updated(scope)

      search_params.each do |name, definition|
        value = resolve_value(name, definition)
        next if value.blank?

        scope = apply_filter(scope, definition, value)
      end

      total = scope.count
      count = clamped_count
      offset = clamped_offset
      records = scope.order(:id).limit(count).offset(offset)

      Result.new(records: records, total: total, count: count, offset: offset)
    end

    private

    attr_reader :resource_type, :model, :search_params, :params

    def filter_id(scope)
      return scope if params["_id"].blank?

      scope.where(id: params["_id"])
    end

    def filter_last_updated(scope)
      return scope if params["_lastUpdated"].blank?

      apply_date_filter(scope, "last_updated", params["_lastUpdated"], :datetime)
    end

    def resolve_value(name, definition)
      value = params[name]
      return value unless definition[:type] == :reference

      value.presence || Array(definition[:aliases]).map { |a| params[a] }.find(&:present?)
    end

    def apply_filter(scope, definition, value)
      case definition[:type]
      when :string then scope.where("#{definition[:column]} ILIKE ?", like_pattern(value))
      when :token then scope.where(definition[:column] => value)
      when :boolean then scope.where(definition[:column] => ActiveModel::Type::Boolean.new.cast(value))
      when :date then apply_date_filter(scope, definition[:column], value, :date)
      when :datetime then apply_date_filter(scope, definition[:column], value, :datetime)
      when :reference then apply_reference_filter(scope, definition, value)
      when :identifier then apply_identifier_filter(scope, value)
      when :token_or_text then apply_token_or_text_filter(scope, definition, value)
      else raise ArgumentError, "Unknown search param type: #{definition[:type]}"
      end
    end

    def apply_reference_filter(scope, definition, value)
      reference = value.include?("/") ? value : "#{definition[:target_type]}/#{value}"
      scope.where(definition[:column] => reference)
    end

    def apply_identifier_filter(scope, value)
      ids = if value.include?("|")
              system, val = value.split("|", 2)
              ResourceIdentifier.where(resource_type: resource_type, system: system, value: val).select(:resource_id)
            else
              ResourceIdentifier.where(resource_type: resource_type, value: value).select(:resource_id)
            end
      scope.where(id: ids)
    end

    def apply_token_or_text_filter(scope, definition, value)
      scope.where(definition[:token_column] => value)
           .or(scope.where("#{definition[:text_column]} ILIKE ?", like_pattern(value)))
    end

    def apply_date_filter(scope, column, value, kind)
      prefix, date_str = split_prefix(value)
      parsed = kind == :date ? parse_date(date_str) : parse_time(date_str)
      return scope unless parsed

      apply_comparison(scope, column, prefix, parsed)
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

    def parse_date(str)
      Date.iso8601(str)
    rescue ArgumentError, TypeError
      nil
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
end
