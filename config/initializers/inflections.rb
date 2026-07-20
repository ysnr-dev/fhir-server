# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# Rails' default "men -> man" rule mis-singularizes "specimen" to "speciman", so
# "Specimen".tableize would yield "specimen" instead of "specimens". Pin the correct
# FHIR Specimen <-> specimens mapping so the model resolves its table name normally.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "specimen", "specimens"
end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end
